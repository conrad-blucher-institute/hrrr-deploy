#!/bin/bash

# Docker wrapper for HRRR extraction testing
# Usage: ./run-test.sh <input_grib2_file> <output_csv_file>
# Example: ./run-test.sh data/working/hrrr.20150219/hrrr.t00z.wrfnatf01.grib2 test-output/test-result.csv

set -e

# Check arguments
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <input_grib2_file> <output_csv_file>"
    echo "Example: $0 data/working/hrrr.20150219/hrrr.t00z.wrfnatf01.grib2 test-output/test-result.csv"
    echo ""
    echo "Note: Paths should be relative to the project root directory"
    echo "      Input file should be under ./data/"
    echo "      Output file will be created under ./test-output/"
    exit 1
fi

INPUT_GRIB2="$1"
OUTPUT_CSV="$2"

# Ensure the input path starts with data/ for Docker volume mounting
if [[ ! "$INPUT_GRIB2" =~ ^data/ ]]; then
    echo "Error: Input GRIB2 file must be under the 'data/' directory"
    echo "Example: data/working/hrrr.20150219/hrrr.t00z.wrfnatf01.grib2"
    exit 1
fi

# Create test-output directory if it doesn't exist
mkdir -p test-output

echo "Starting Docker container for HRRR extraction test..."

# Start the test container
docker compose -f docker-compose.test.yml up -d

# Wait a moment for container to be ready
sleep 2

echo "Running extraction test in container..."
echo "Input: $INPUT_GRIB2"
echo "Output: $OUTPUT_CSV"
echo

# Convert paths for inside the container
CONTAINER_INPUT="/${INPUT_GRIB2}"
CONTAINER_OUTPUT="/${OUTPUT_CSV}"

# Run the test inside the container
docker compose -f docker-compose.test.yml exec -T hrrr-test bash -c "
    cd /opt
    echo 'Container working directory: '\$(pwd)
    echo 'Available files:'
    ls -la /opt/
    echo
    echo 'Input file check:'
    if [[ -f '$CONTAINER_INPUT' ]]; then
        echo 'Input file exists: $CONTAINER_INPUT'
        echo 'File size: '\$(ls -lh '$CONTAINER_INPUT' | awk '{print \$5}')
    else
        echo 'Error: Input file not found: $CONTAINER_INPUT'
        echo 'Available files in /data:'
        find /data -name '*.grib2' | head -10
        exit 1
    fi
    echo
    
    echo 'Running extraction test...'
    ./test-extraction.sh '$CONTAINER_INPUT' '$CONTAINER_OUTPUT'
"

# Copy the output file to the host if it was created inside the container
if docker compose -f docker-compose.test.yml exec -T hrrr-test test -f "/$OUTPUT_CSV"; then
    echo
    echo "Test completed successfully!"
    echo "Output file created: $OUTPUT_CSV"
    
    # Show output file info
    if [[ -f "$OUTPUT_CSV" ]]; then
        echo "Local output file size: $(wc -l < "$OUTPUT_CSV") lines"
    fi
else
    echo
    echo "Test completed, but output file may not have been created."
fi

echo
echo "Stopping test container..."
docker compose -f docker-compose.test.yml down

echo "Test finished!"
