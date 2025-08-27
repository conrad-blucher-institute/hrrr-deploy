#!/bin/bash

# Simple test script to download one HRRR file and test extraction
# Usage: ./test-single-file.sh [date] [cycle] [forecast_lead]
# Example: ./test-single-file.sh 20190102 00 01

set -e

# Default values if not provided
TEST_DATE=${1:-20160101}
TEST_CYCLE=${2:-00}
TEST_LEAD=${3:-01}

echo "=== HRRR Single File Download and Extraction Test ==="
echo "Date: $TEST_DATE"
echo "Cycle: $TEST_CYCLE"
echo "Forecast Lead: $TEST_LEAD"


# HRRR file details
HRRR_FILE="hrrr.t${TEST_CYCLE}z.wrfsfcf${TEST_LEAD}.grib2"
S3_URL="s3://noaa-hrrr-bdp-pds/hrrr.${TEST_DATE}/conus/${HRRR_FILE}"
LOCAL_FILE="$HRRR_DOWNLOAD_PATH/$HRRR_FILE"
OUTPUT_CSV="$HRRR_OUTPUT_PATH/test-extraction.csv"

echo "=== Step 1: Download HRRR file ==="
echo "Source: $S3_URL"
echo "Local: $LOCAL_FILE"

if [[ -f "$LOCAL_FILE" ]]; then
    echo "File already exists locally, skipping download"
    echo "File size: $(ls -lh "$LOCAL_FILE" | awk '{print $5}')"
else
    echo "Downloading file..."
    if ! aws s3 cp "$S3_URL" "$LOCAL_FILE" --no-sign-request; then
        echo "ERROR: Failed to download $S3_URL"
        echo "This could mean:"
        echo "  - The file doesn't exist for this date/time"
        echo "  - AWS CLI is not available"
        echo "  - Network connectivity issues"
        exit 1
    fi
    echo "Download completed successfully"
    echo "File size: $(ls -lh "$LOCAL_FILE" | awk '{print $5}')"
fi

echo
echo "=== Step 2: Test extraction ==="
echo "Input: $LOCAL_FILE"
echo "Output: $OUTPUT_CSV"

# Run the test extraction
if bash /opt/test-extraction.sh "$LOCAL_FILE" "$OUTPUT_CSV"; then
    echo
    echo "=== Step 3: Results ==="
    if [[ -f "$OUTPUT_CSV" ]]; then
        echo "✅ Extraction successful!"
        echo "Output file: $OUTPUT_CSV"
        echo "Lines in output: $(wc -l < "$OUTPUT_CSV")"
        
        echo
        echo "=== CSV Header ==="
        head -1 "$OUTPUT_CSV"
        
        echo
        echo "=== Sample Data (first 3 lines) ==="
        head -3 "$OUTPUT_CSV"
        
        echo
        echo "=== Data Summary ==="
        if [[ $(wc -l < "$OUTPUT_CSV") -gt 1 ]]; then
            tail -n +2 "$OUTPUT_CSV" | awk -F',' '
            BEGIN {
                print "Variable analysis:"
                vars[5] = "PRATE_surface"
                vars[6] = "TMP_2_m_above_ground" 
                vars[7] = "DPT_2_m_above_ground"
                vars[8] = "PWAT_entire_atmosphere_(considered_as_a_single_layer)"
                vars[9] = "VUCSH_0-6000_m_above_ground"
                vars[10] = "VVCSH_0-6000_m_above_ground"
                vars[11] = "CAPE_90-0_mb_above_ground"
            }
            {
                for (i = 5; i <= 11; i++) {
                    if ($i != "") count[i]++
                }
                total_rows++
            }
            END {
                printf "Total data rows: %d\n", total_rows
                for (i = 5; i <= 11; i++) {
                    printf "%-50s: %d values\n", vars[i], count[i]
                }
            }'
        else
            echo "Only header present - no data extracted"
        fi
    else
        echo "❌ Extraction failed - no output file created"
        exit 1
    fi
else
    echo "❌ Extraction script failed"
    exit 1
fi

echo
echo "=== Test Summary ==="
echo "✅ Downloaded: $LOCAL_FILE"
echo "✅ Extracted: $OUTPUT_CSV"
echo "🎯 Test completed successfully!"
echo
echo "To clean up test files: rm -rf $TEST_DIR"
