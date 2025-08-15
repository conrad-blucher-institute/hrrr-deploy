#!/bin/bash

shopt -s extglob    # Extended globbing (pattern matching) support

# HRRR data extraction for Oso Creek / Corpus Christi basin
# Extracts raw precipitation rate (prate) data from HRRR deterministic runs
# Time Range: February 19, 2015 through March 6, 2021
# Forecast leads: 1-15 hours
# Location: Oso Creek / Corpus Christi basin (lat/lon box)
# Output: Raw precipitation data in kg/m²/s

# Oso Creek / Corpus Christi basin coordinates
# Lat/Lon bounds: (27.588733, 27.837343, -97.729247, -97.251896)
LAT_MIN=27.588733
LAT_MAX=27.837343
LON_MIN=-97.729247
LON_MAX=-97.251896

# Convert longitude to 0-360 format for HRRR data using bash arithmetic
# Since we're dealing with known values, we can precompute them
LON_MIN_360="262.270753"  # -97.729247 + 360
LON_MAX_360="262.748104"  # -97.251896 + 360

echo "Processing Oso Creek / Corpus Christi basin:"
echo "  Latitude range: $LAT_MIN to $LAT_MAX"
echo "  Longitude range: $LON_MIN to $LON_MAX (-180 to 180)"
echo "  Longitude range: $LON_MIN_360 to $LON_MAX_360 (0 to 360)"

# Download HRRR archive files for specific date and forecast leads 1-15
download_date_prediction_leads() {
    local date=$1
    local prediction_hour=`printf "%02d" $2`
    local dl_path=$3

    # S3 path for HRRR data
    local s3_path="s3://noaa-hrrr-bdp-pds/hrrr.${date}/conus/"
    
    # Download forecast leads 01-15 (f01 through f15)
    local dl_start=`date '+%s'`
    echo " • Checking/downloading forecast leads 01-15 from $s3_path for hour $prediction_hour"
    
    local downloaded_count=0
    local skipped_count=0
    
    # Download each forecast lead individually, but check if already exists
    for lead in {01..15}; do
        local s3_obj_name="hrrr.t${prediction_hour}z.wrfnatf${lead}.grib2"
        local local_file_path="$dl_path/$s3_obj_name"
        
        if [[ -f "$local_file_path" ]]; then
            echo "   - Skipping $s3_obj_name (already downloaded)"
            skipped_count=$((skipped_count + 1))
        else
            echo "   - Downloading $s3_obj_name"
            aws s3 cp --no-progress "${s3_path}${s3_obj_name}" "$dl_path/" --no-sign-request
            downloaded_count=$((downloaded_count + 1))
        fi
    done
    
    local dl_end=`date '+%s'`
    local dl_delta=$((dl_end - dl_start))

    # Keep track of download size and stats
    local size_mb=`du -sm "$dl_path" | cut -f1`
    echo "# Download summary: $downloaded_count new, $skipped_count existing files"
    echo "# $size_mb MB total in download path, completed in $dl_delta seconds"
    return
}

# Extract precipitation rate (prate) data for the Oso Creek basin lat/lon box
extract_prate_basin_data() {
    local path2gribs=$1
    local output_file=$2

    # Create header for CSV output
    echo "datetime,forecast_lead,lat,lon,prate" > "$output_file"

    for grib_file in $path2gribs/*.grib2; do
        # In case of no files
        [[ ! -e "$grib_file" ]] && continue
        
        local filename=$(basename "$grib_file")
        echo " • Processing $filename" 1>&2
        
        # Extract date, hour, and forecast lead from filename
        # Format: hrrr.tHHz.wrfnatfLL.grib2 where HH=hour, LL=lead
        local run_hour=$(echo "$filename" | sed -n 's/.*\.t\([0-9][0-9]\)z\..*/\1/p')
        local forecast_lead=$(echo "$filename" | sed -n 's/.*\.wrfnatf\([0-9][0-9]\)\.grib2/\1/p')
        
        # Get the date from the parent directory path
        local run_date=$(echo "$path2gribs" | sed -n 's/.*hrrr\.\([0-9]\{8\}\).*/\1/p')
        if [[ -z "$run_date" ]]; then
            # If we can't extract from path, use current processing date
            run_date=$(basename $(dirname "$path2gribs"))
        fi
        
        # Create datetime string
        local datetime="${run_date:0:4}-${run_date:4:2}-${run_date:6:2}T${run_hour}:00:00Z"
        
        # Extract precipitation rate data for the specified lat/lon box
        # Use wgrib2 to extract prate variable within the bounding box
        wgrib2 "$grib_file" -match "PRATE" -small_grib ${LON_MIN_360}:${LON_MAX_360} ${LAT_MIN}:${LAT_MAX} /tmp/subset.grib2 >/dev/null 2>&1
        
        if [[ -f /tmp/subset.grib2 ]]; then
            # Extract data in CSV format
            wgrib2 /tmp/subset.grib2 -csv /tmp/prate_data.csv >/dev/null 2>&1
            
            if [[ -f /tmp/prate_data.csv ]]; then
                # Process CSV data - save raw values without conversion
                while IFS=',' read -r start_date end_date var_name var_level lon lat value; do
                    # Skip header line
                    [[ "$start_date" == "start_date" ]] && continue
                    
                    # Convert longitude to -180 to 180 range for output
                    # wgrib2 may output longitude in different formats depending on the data
                    
                    if (( $(awk "BEGIN {print ($lon > 180)}") )); then
                        # Longitude is in 0-360 format, convert to -180 to 180
                        local lon_180=$(awk "BEGIN {print $lon - 360}")
                    else
                        # Longitude is already in -180 to 180 format, use as-is
                        local lon_180=$lon
                    fi
                    
                    # Output: datetime, forecast_lead, lat, lon, prate_value
                    echo "$datetime,$forecast_lead,$lat,$lon_180,$value" >> "$output_file"
                    
                done < /tmp/prate_data.csv
                
                rm -f /tmp/prate_data.csv
            fi
            
            rm -f /tmp/subset.grib2
        fi
        
        PROCESS_COUNT=$((PROCESS_COUNT + 1))
    done
}

# Process HRRR grib files for specific date and prediction hour
process_hrrr_prate() {
    local pred_date=$1
    local prediction_hour=`printf "%02d" $2`

    local now=`date -u '+%Y-%m-%dT%H:%M:%SZ'`
    echo "# Starting HRRR prate processing (date $pred_date, prediction hour $prediction_hour) at $now" >>$LOG_FILE

    # Create date-specific download directory
    local date_download_path="$HRRR_DOWNLOAD_PATH/hrrr.$pred_date"
    mkdir -p "$date_download_path"

    download_date_prediction_leads $pred_date $prediction_hour "$date_download_path" >>$LOG_FILE 2>&1
    
    local prate_output_file="$pred_date-$prediction_hour-prate-raw.csv"
    extract_prate_basin_data "$date_download_path" "$HRRR_OUTPUT_PATH/$prate_output_file" 2>>$LOG_FILE
    
    # Compress output file to save space
    local prate_output_zip=$(echo $prate_output_file | sed 's/\.csv$/.zip/')
    cd $HRRR_OUTPUT_PATH
    zip -q "$prate_output_zip" "$prate_output_file" \
        && rm "$prate_output_file" >>$LOG_FILE 2>&1
    cd -

    echo " • Removing downloaded grib2 files" >>$LOG_FILE
    rm -rf "$date_download_path" >>$LOG_FILE 2>&1

    local now=`date -u '+%Y-%m-%dT%H:%M:%SZ'`
    echo "# Finished processing ($pred_date, prediction hour $prediction_hour) at $now" >>$LOG_FILE
}

# Archive results locally (no S3 upload)
archive_results() {
    local output_path=$1

    for i in $output_path/*.zip; do
        [[ ! -e "$i" ]] && continue
        echo " • Archiving $i locally"
        mv "$i" $HRRR_ARCHIVE_PATH \
            && echo "   ... Successfully archived $i to $HRRR_ARCHIVE_PATH"
    done
}

# Convert from julian/ordinal day to YYYYMMDD
jul2ymd() {
    date -d "$1-01-01 +$2 days -1 day" "+%Y%m%d"
}

# Print usage and die
usage() {
    local zero=`basename $0`
    cat <<EndOfUsage 1>&2
Usage:  $zero [start_date] [end_date]

Extract HRRR precipitation rate data for Oso Creek / Corpus Christi basin
Time Range: February 19, 2015 through March 6, 2021 (default)
Forecast leads: 1-15 hours
All prediction hours (00-23) will be processed

<start_date> and <end_date> must be in the format YYYYMMDD
If no dates provided, will process the full default range

Examples:
---------
Process full default range (Feb 19, 2015 - Mar 6, 2021):
    $zero

Process specific date range:
    $zero 20150219 20150228

Process single day:
    $zero 20150219 20150219

EndOfUsage
    exit 1
}

# Parse command line arguments
START_DATE=${1:-"20150219"}  # Default: February 19, 2015
END_DATE=${2:-"20210306"}    # Default: March 6, 2021

# Validate date format
if [[ ! "$START_DATE" =~ ^[0-9]{8}$ ]] || [[ ! "$END_DATE" =~ ^[0-9]{8}$ ]]; then
    echo "Error: Dates must be in YYYYMMDD format" 1>&2
    usage
fi

echo "Processing HRRR precipitation data for Oso Creek / Corpus Christi basin"
echo "Date range: $START_DATE to $END_DATE"
echo "Forecast leads: 1-15 hours"
echo "Prediction hours: 00-23"

# Ensure directory infrastructure exists
mkdir -p $HRRR_DOWNLOAD_PATH $HRRR_OUTPUT_PATH $HRRR_ARCHIVE_PATH $HRRR_LOG_PATH

# Log file
TODAY=`date -u '+%Y%m%d'`
LOG_FILE="$HRRR_LOG_PATH/hrrr-prate-oso-creek-$TODAY.log"

# Put machine-specific metadata at start of logfile
if [[ ! -e "$LOG_FILE" ]]; then
    cat > "$LOG_FILE" << EOF
# HRRR Precipitation Rate Extraction for Oso Creek / Corpus Christi Basin
# Hostname: $(hostname)
# $(uname -ar)
# wgrib2 version: $(wgrib2 -version 2>/dev/null || echo "wgrib2 not found")
# Processing range: $START_DATE to $END_DATE
# Basin coordinates: Lat($LAT_MIN, $LAT_MAX), Lon($LON_MIN, $LON_MAX)
# Forecast leads: 1-15 hours
# Variable: Precipitation rate (prate)
# Units: Raw kg/m²/s (no conversion)
EOF
fi

# Check for required tools
for tool in wgrib2 aws; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: Required tool '$tool' not found" 1>&2
        echo "Please ensure wgrib2 and aws-cli are installed" 1>&2
        exit 1
    fi
done

# Number of total grib2 files processed
PROCESS_COUNT=0

# Start timer
START_TIME=`date '+%s'`
echo "" >>$LOG_FILE

# Convert dates to julian format for iteration
read year1 doy1 <<< $(date -d "$START_DATE" "+%Y %j")
read year2 doy2 <<< $(date -d "$END_DATE" "+%Y %j")

# Force decimal context
doy1=$((10#$doy1))
doy2=$((10#$doy2))

echo "Processing HRRR prate data from $START_DATE [$year1 $doy1] to $END_DATE [$year2 $doy2]" >>$LOG_FILE

day_count=0
y=$year1
d=$doy1

# Main processing loop
while (( y < year2 )) || (( y == year2 && d <= doy2 )); do
    when=`jul2ymd "$y" "$d"`
    
    # Skip invalid dates (e.g., Feb 29 in non-leap years)
    if [[ ${when:0:4} -eq "$y" ]]; then
        echo "Processing date: $when"
        
        # Process all prediction hours (00-23) for each day
        for ph in {00..23}; do
            echo "  Processing prediction hour: $ph"
            process_hrrr_prate $when $ph
        done
        
        # Archive results for this day (no S3 upload)
        archive_results "$HRRR_OUTPUT_PATH" >>$LOG_FILE 2>&1
    fi

    d=$((d + 1))
    day_count=$((day_count + 1))

    # Handle day overflow (366 for leap years)
    if (( d > 366 )); then
        d=1
        y=$((y + 1))
    fi

    # Progress reporting
    END_TIME=`date '+%s'`
    DELTA=$((END_TIME - START_TIME))
    echo "# [Day $day_count] Processed $PROCESS_COUNT HRRR grib2 files in $DELTA seconds" >>$LOG_FILE
    echo "Progress: Day $day_count completed ($when)"
done

# Final statistics
END_TIME=`date '+%s'`
DELTA=$((END_TIME - START_TIME))
echo "# [Final] Processed $PROCESS_COUNT HRRR grib2 files in $DELTA seconds" >>$LOG_FILE
echo "Processing complete. Total time: $DELTA seconds, Files processed: $PROCESS_COUNT"

# Estimate total runs processed
total_days=$day_count
total_prediction_hours=$((total_days * 24))
total_forecast_leads=$((total_prediction_hours * 15))
echo "# Statistics: $total_days days, $total_prediction_hours prediction hours, $total_forecast_leads forecast leads" >>$LOG_FILE
echo "Estimated total forecast files processed: $total_forecast_leads"
