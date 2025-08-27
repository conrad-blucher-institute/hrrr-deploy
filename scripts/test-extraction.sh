#!/bin/bash

# Test script for HRRR data extraction
# Usage: ./test-extraction.sh <input_grib2_file> <output_csv_file>
# Example: ./test-extraction.sh data/working/hrrr.20150219/hrrr.t00z.wrfsfcf01.grib2 test-output.csv

set -e  # Exit on any error

# Check arguments
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <input_grib2_file> <output_csv_file>"
    echo "Example: $0 data/working/hrrr.20150219/hrrr.t00z.wrfsfcf01.grib2 test-output.csv"
    exit 1
fi

INPUT_GRIB2="$1"
OUTPUT_CSV="$2"

# Check if input file exists
if [[ ! -f "$INPUT_GRIB2" ]]; then
    echo "Error: Input GRIB2 file does not exist: $INPUT_GRIB2"
    exit 1
fi

# Create output directory if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT_CSV")
mkdir -p "$OUTPUT_DIR"

echo "Testing HRRR extraction..."
echo "Input GRIB2 file: $INPUT_GRIB2"
echo "Output CSV file: $OUTPUT_CSV"
echo

# Oso Creek / Corpus Christi basin coordinates (same as main script)
LAT_MIN=27.588733
LAT_MAX=27.837343
LON_MIN=-97.729247
LON_MAX=-97.251896

# Convert longitude to 0-360 format for HRRR data
LON_MIN_360="262.270753"  # -97.729247 + 360
LON_MAX_360="262.748104"  # -97.251896 + 360

echo "Geographic bounds:"
echo "  Latitude: $LAT_MIN to $LAT_MAX"
echo "  Longitude: $LON_MIN to $LON_MAX (-180 to 180)"
echo "  Longitude: $LON_MIN_360 to $LON_MAX_360 (0 to 360)"
echo

# Test extraction function (copied from main script)
test_extract_hrrr_basin_data() {
    local input_grib=$1
    local output_file=$2

    # Define variables and their exact level strings as they appear in GRIB files
    declare -A variables_levels=(
        ["PRATE"]="surface"
        ["TMP"]="2 m above ground"
        ["DPT"]="2 m above ground" 
        ["PWAT"]="entire atmosphere (considered as a single layer)"
        ["VUCSH"]="0-6000 m above ground"
        ["VVCSH"]="0-6000 m above ground"
        ["CAPE"]="90-0 mb above ground"
    )

    # Create header with variable+level columns (spaces replaced with underscores)
    local header="start_time,long,lat,valid_time"
    for variable in PRATE TMP DPT PWAT VUCSH VVCSH CAPE; do
        local level="${variables_levels[$variable]}"
        header="${header},${variable}_${level// /_}"
    done
    echo "$header" > "$output_file"

    # Use associative arrays to store data by location+time
    declare -A data_matrix
    declare -A locations_times

    local filename=$(basename "$input_grib")
    echo "Processing $filename..."
    
    # Check what variables are available in the file
    echo "Available variables in GRIB file:"
    wgrib2 "$input_grib" -var -lev | head -20
    echo
    
    # Step 1: Create geographic subset once
    local subset_file="/tmp/test_subset_$(basename "$input_grib" .grib2).grib2"
    echo "Creating geographic subset..."
    
    if ! wgrib2 "$input_grib" -small_grib ${LON_MIN_360}:${LON_MAX_360} ${LAT_MIN}:${LAT_MAX} "$subset_file"; then
        echo "Error: Failed to create geographic subset from $filename"
        return 1
    fi
    
    echo "Subset created successfully: $subset_file"
    echo "Variables in subset:"
    wgrib2 "$subset_file" -var -lev
    echo
    
    # Step 2: Extract each variable separately (like the main script)
    local temp_csv="/tmp/test_all_variables_$(basename "$input_grib" .grib2).csv"
    echo "Extracting all variables from subset..."
    
    # Create empty temp CSV file
    > "$temp_csv"
    
    # Extract each variable separately
    for variable in "${!variables_levels[@]}"; do
        local level="${variables_levels[$variable]}"
        echo "   - Extracting $variable at $level"
        
        # Extract variable at specific level from the subset
        local var_subset="/tmp/subset_${variable}_$(basename "$input_grib" .grib2).grib2"
        
        # Escape parentheses in level string for regex matching
        local escaped_level="${level//\(/\\(}"
        escaped_level="${escaped_level//\)/\\)}"
        
        if wgrib2 "$subset_file" -match ":$variable:$escaped_level:" -grib "$var_subset" >/dev/null 2>&1; then
            # Convert to CSV and append to main CSV
            local var_csv="/tmp/${variable}_data_$(basename "$input_grib" .grib2).csv"
            if wgrib2 "$var_subset" -csv "$var_csv" >/dev/null 2>&1; then
                # Append to main CSV file (skip header if not first variable)
                if [[ -s "$temp_csv" ]]; then
                    # Skip header line when appending
                    tail -n +2 "$var_csv" >> "$temp_csv"
                else
                    # Include header for first variable
                    cat "$var_csv" >> "$temp_csv"
                fi
                rm -f "$var_csv"
            fi
            rm -f "$var_subset"
        else
            echo "   - Warning: No data found for $variable at $level"
        fi
    done

    # Show what was extracted
    if [[ -f "$temp_csv" ]] && [[ -s "$temp_csv" ]]; then
        echo "Extraction successful. Sample of extracted data:"
        echo "CSV file has $(wc -l < "$temp_csv") lines"
        head -5 "$temp_csv"
        echo "..."
        echo
    else
        echo "Warning: No data was extracted to CSV file"
        # Try a broader extraction to see what's available
        echo "Trying broader extraction to see available data..."
        wgrib2 "$subset_file" -csv "/tmp/broad_extract.csv"
        if [[ -f "/tmp/broad_extract.csv" ]] && [[ -s "/tmp/broad_extract.csv" ]]; then
            echo "Broad extraction found $(wc -l < "/tmp/broad_extract.csv") lines:"
            head -10 "/tmp/broad_extract.csv"
        fi
        rm -f "/tmp/broad_extract.csv"
    fi

    # Clean up subset file
    rm -f "$subset_file"

    # Process the CSV output containing all variables (if any)
    if [[ ! -f "$temp_csv" ]] || [[ ! -s "$temp_csv" ]]; then
        echo "No data extracted - creating empty output file with header only"
        return 0
    fi

    # Read the CSV and organize data by location+time
    local line_count=0
    while IFS=',' read -r start_time valid_time variable level longitude latitude value; do
        line_count=$((line_count + 1))
        
        # Remove quotes if present
        start_time=${start_time//\"/}
        valid_time=${valid_time//\"/}
        variable=${variable//\"/}
        level=${level//\"/}
        longitude=${longitude//\"/}
        latitude=${latitude//\"/}
        value=${value//\"/}
        
        # Skip empty lines
        [[ -z "$start_time" || -z "$variable" ]] && continue
        
        # Create location+time key
        local location_time_key="${start_time},${longitude},${latitude},${valid_time}"
        
        # Store this location+time combination
        locations_times["$location_time_key"]=1
        
        # Create variable+level key (replace spaces with underscores)
        local var_level_key="${variable}_${level// /_}"
        
        # Store the value for this location+time+variable combination
        data_matrix["${location_time_key}|${var_level_key}"]="$value"
        
    done < "$temp_csv"
    
    echo "Processed $line_count lines from CSV"
    echo "Found ${#locations_times[@]} unique location+time combinations"
    
    # Clean up temporary file
    rm -f "$temp_csv"

    # Write out the pivoted data
    echo "Writing pivoted output..."
    local output_lines=0
    for location_time in "${!locations_times[@]}"; do
        # Start with the location+time data
        local output_line="$location_time"
        
        # Add each variable+level value in the specified order
        for variable in PRATE TMP DPT PWAT VUCSH VVCSH CAPE; do
            local level="${variables_levels[$variable]}"
            local var_level_key="${variable}_${level// /_}"
            local value="${data_matrix[${location_time}|${var_level_key}]:-}"
            output_line="${output_line},${value}"
        done
        
        echo "$output_line" >> "$output_file"
        output_lines=$((output_lines + 1))
    done
    
    echo "Wrote $output_lines data lines to $output_file"
}

# Run the test
echo "Starting extraction test..."
test_extract_hrrr_basin_data "$INPUT_GRIB2" "$OUTPUT_CSV"

echo
echo "Test completed!"
echo "Output file: $OUTPUT_CSV"

if [[ -f "$OUTPUT_CSV" ]]; then
    echo "Output file size: $(wc -l < "$OUTPUT_CSV") lines"
    echo "Sample output:"
    head -3 "$OUTPUT_CSV"
    
    # Show summary of non-empty values
    echo
    echo "Summary of extracted data:"
    if [[ $(wc -l < "$OUTPUT_CSV") -gt 1 ]]; then
        # Count non-empty values in each column
        tail -n +2 "$OUTPUT_CSV" | awk -F',' '
        BEGIN {
            print "Column analysis (non-empty values):"
        }
        NR == 1 {
            # Get header from first data line to count columns
            split($0, fields, ",")
            for (i = 1; i <= NF; i++) {
                count[i] = 0
            }
        }
        {
            split($0, fields, ",")
            for (i = 1; i <= NF; i++) {
                if (fields[i] != "") count[i]++
            }
        }
        END {
            for (i = 1; i <= NF; i++) {
                printf "Column %d: %d non-empty values\n", i, count[i]
            }
        }'
    else
        echo "Only header present - no data extracted"
    fi
else
    echo "Error: Output file was not created"
fi
