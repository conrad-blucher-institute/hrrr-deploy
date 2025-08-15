#!/bin/bash

# Debug script to understand wgrib2 output format

echo "=== Debugging wgrib2 longitude output ==="

GRIB_FILE="/srv/download/hrrr.20200101/hrrr.t00z.wrfnatf01.grib2"

if [[ ! -f "$GRIB_FILE" ]]; then
    echo "Error: GRIB file not found: $GRIB_FILE"
    exit 1
fi

echo "1. Extracting subset with wgrib2..."
wgrib2 "$GRIB_FILE" -match "PRATE" -small_grib 262.270753:262.748104 27.588733:27.837343 /tmp/debug_subset.grib2

echo "2. Converting to CSV..."
wgrib2 /tmp/debug_subset.grib2 -csv /tmp/debug_data.csv

echo "3. First 10 lines of CSV output:"
head -10 /tmp/debug_data.csv

echo "4. Sample of longitude values:"
awk -F, 'NR>1 {print "Line " NR ": lon=" $5 ", lat=" $6}' /tmp/debug_data.csv | head -5

echo "5. Min/Max longitude values:"
awk -F, 'NR>1 {print $5}' /tmp/debug_data.csv | sort -n | head -1 | xargs echo "Min longitude:"
awk -F, 'NR>1 {print $5}' /tmp/debug_data.csv | sort -n | tail -1 | xargs echo "Max longitude:"

echo "6. Expected longitude range: -97.729247 to -97.251896"
echo "7. Expected longitude range (0-360): 262.270753 to 262.748104"

# Cleanup
rm -f /tmp/debug_subset.grib2 /tmp/debug_data.csv
