# HRRR Precipita# 4. Run full extraction (2-4 weeks)
# Edit .env: RUN_COMMAND=/opt/aws-process-hrrr.sh
docker compose up

# 5. Access extracted data
# Raw CSV files will be available in ./data/archive/
ls ./data/archive/
```a Extraction

This project extracts and analyzes High-Resolution Rapid Refresh (HRRR) precipitation data for the Oso Creek / Corpus Christi basin from the NOAA HRRR archive on AWS S3.

## Quick Start

```bash
# 1. Clone and setup
git clone <repository-url>
cd hrrr-deploy
./setup.sh

# 2. Test with single day
# Edit .env: RUN_COMMAND=/opt/aws-process-hrrr.sh 20200101 20200101
docker compose up

# 3. Run full extraction (2-4 weeks)
# Edit .env: RUN_COMMAND=/opt/aws-process-hrrr.sh
docker compose up

# 5. Analyze results
docker compose run --rm wgrib2 python3 /opt/analyze-hrrr-precipitation.py \
    --data-dir /srv/archive --output-dir /srv/analysis
```

**Important**: Always run Docker Compose commands from the project root directory (where `docker-compose.yml` is located) since the configuration uses relative paths.

## Overview

The extraction focuses on:
- **Time Range**: February 19, 2015, through March 6, 2021 (inclusive)
- **Forecast Leads**: Hours 1-15 for each run
- **Location**: Oso Creek / Corpus Christi basin (Lat: 27.588733-27.837343, Lon: -97.729247 to -97.251896)
- **Variable**: Precipitation rate (prate) converted from kg/m²/s to mm/hr
- **Total**: Approximately 53,000 runs with ~795,000 forecast files

## Files

### Extraction Scripts
- `aws-process-hrrr.sh` - Main extraction script using wgrib2 for Oso Creek basin

### Configuration
- `etc/sample-environment.sh` - Environment configuration template
- `requirements.txt` - Python dependencies (not needed for basic extraction)

### Docker
- `docker-compose.yml` - Docker configuration for containerized processing

## Checkpoint Feature

The extraction script includes a checkpoint system that allows processing to resume from where it left off if the container is stopped or crashes:

- **Enabled by default**: Set `ENABLE_CHECKPOINT=true` in environment or `.env` file
- **Disable checkpoints**: Set `ENABLE_CHECKPOINT=false` to always start from the beginning
- **Checkpoint file**: `data/output/processing_checkpoint.txt` stores current position as `year,day_of_year,hour`
- **Manual control**: You can manually edit the checkpoint file to resume from a specific date/time

**Examples:**
```bash
# Run with checkpoints enabled (default)
ENABLE_CHECKPOINT=true docker compose up

# Run without checkpoints (always start from beginning)
ENABLE_CHECKPOINT=false docker compose up

# Manually set checkpoint to January 15, 2020, hour 12
echo "2020,15,12" > data/output/processing_checkpoint.txt
```

## Requirements

### System Requirements
- Docker and Docker Compose installed
- At least 100GB free disk space for processing
- Reliable internet connection for S3 downloads

### Docker Setup
All dependencies (wgrib2, AWS CLI, bc, Python) are included in the Docker container. No local installation required.

### Installation

#### Quick Setup (Recommended)
```bash
# Clone the repository
git clone <repository-url>
cd hrrr-deploy

# Run the setup script
./setup.sh

# This will:
# - Create .env file with correct paths
# - Create data directory structure  
```

#### Manual Setup
```bash
# Clone the repository
git clone <repository-url>
cd hrrr-deploy

# Copy and configure environment (paths are already set to relative)
cp etc/sample-environment.sh .env
# No path editing needed - uses ./scripts and ./data

# Create data directories
mkdir -p data/{download,output,archive,logs,analysis}

# Test setup
docker-compose run --rm wgrib2 /opt/validate-setup.sh
```

## Usage

### 1. Environment Setup
```bash
# Copy environment template
cp etc/sample-environment-oso-creek.sh .env

# Edit with your local host paths
nano .env
```

Required environment variables in `.env`:
- `HOST_SCRIPT_ABS_DIR=./scripts` - Relative path to scripts directory
- `HOST_DATA_ABS_DIR=./data` - Relative path to data directory  
- `RUN_COMMAND` - Command to run in container (default: `/opt/aws-process-hrrr.sh`)

Container environment variables (set automatically):
- `HRRR_BASE_PATH=/srv/` - Base directory inside container
- `HRRR_DOWNLOAD_PATH=/srv/download` - Temporary download directory
- `HRRR_OUTPUT_PATH=/srv/output` - Output directory for processed files
- `HRRR_ARCHIVE_PATH=/srv/archive` - Archive directory for completed files
- `HRRR_LOG_PATH=/srv/logs` - Log file directory
- `AWS_DEFAULT_REGION=us-east-1` - AWS region for accessing public HRRR data

**Note**: The paths use relative directories (`./scripts` and `./data`) so Docker Compose must be run from the project root directory. No AWS credentials are required as the HRRR data is publicly accessible. All processed data will be saved to your host `./data` directory.

### 2. Data Extraction

#### Full Date Range (Default)
```bash
# Build and run container for complete dataset (Feb 19, 2015 - Mar 6, 2021)
docker-compose up --build
```

#### Custom Date Range
```bash
# Edit .env file to specify custom command
RUN_COMMAND="/opt/aws-process-hrrr-oso-creek.sh 20150219 20150228"

# Run with custom date range
docker-compose up --build
```

#### Interactive Mode for Testing
```bash
# Run container interactively for debugging/testing
docker-compose run --rm wgrib2 bash

# Inside container, you can run:
# /opt/aws-process-hrrr.sh 20200101 20200101  # Single day test
```

### 3. Resume Functionality

The extraction system automatically resumes from where it left off if interrupted:

#### Docker Resume
```bash
# Check resume status
./docker-resume.sh

# Resume processing (existing files will be skipped)
docker compose up

# The script automatically detects and skips existing files
```

#### HPC Resume
```bash
# Check resume status
./submit-hrrr.sh resume

# Resume with new job submission
./submit-hrrr.sh array --tasks 12
```

**Resume Features:**
- ✅ **Automatic detection**: Skips existing ZIP files in archive and output directories
- ✅ **Progress tracking**: Shows completion percentage and remaining files
- ✅ **Flexible restart**: Can change date ranges while preserving existing data
- ✅ **No data loss**: Safe to interrupt and restart at any time

When you restart processing:
1. Existing `.zip` files are automatically detected
2. Only missing files are downloaded and processed
3. Progress statistics show skipped vs. new files
4. Total processing time is reduced significantly

## HPC Usage (Recommended for Large Datasets)

For processing large amounts of HRRR data efficiently, use the HPC SLURM scripts with Singularity containers. See the comprehensive **[HPC Guide (README-HPC.md)](README-HPC.md)** for detailed instructions.

Quick HPC start:
```bash
# Setup and test
./submit-hrrr.sh setup
./submit-hrrr.sh test --date 20200101

# Run parallel processing (recommended)
./submit-hrrr.sh array --tasks 12

# Monitor progress
./submit-hrrr.sh status
```

The HPC approach offers several advantages:
- **Parallel processing**: Process monthly chunks simultaneously
- **Better performance**: Optimized for large-scale data processing
- **Automatic recovery**: Failed tasks can be resubmitted individually
- **Resource efficiency**: Better utilization of computational resources

### 3. Data Access
```bash
# Extracted CSV files are stored in ./data/archive/ as ZIP files
# Extract and view a sample file:
cd ./data/archive
unzip -l 20200101-12-prate-raw.zip
unzip 20200101-12-prate-raw.zip
head 20200101-12-prate-raw.csv
```


## Output Format

### Extracted Data (CSV)
Each forecast generates a CSV file with columns:
- `datetime` - Forecast initialization time (UTC)
- `forecast_lead` - Forecast lead time (hours 1-15)
- `lat` - Latitude of grid point
- `lon` - Longitude of grid point (-180 to 180 format)
- `prate_kg_m2_s` - Raw precipitation rate (kg/m²/s)

Files are compressed as ZIP and stored in `./data/archive/` with naming pattern:
`YYYYMMDD-HH-prate-raw.zip`

## Processing Details

### Spatial Coverage
The extraction uses a lat/lon bounding box to subset HRRR data:
- **Latitude**: 27.588733° to 27.837343° N
- **Longitude**: -97.729247° to -97.251896° W (262.270753° to 262.748104° E)

### Temporal Coverage
- **Start**: February 19, 2015, 00Z
- **End**: March 6, 2021, 23Z
- **Prediction Hours**: 00-23Z (all hours)
- **Forecast Leads**: 1-15 hours

### Unit Conversion
Precipitation data is extracted in its native HRRR units (kg/m²/s). For analysis:
- To convert to mm/hr: multiply by 3600 (since 1 kg/m² = 1 mm depth)
- To convert to inches/hr: multiply by 0.03937 × 3600

## Performance and Resources

### Estimated Processing Time
- **Single day (24 hours × 15 leads = 360 files)**: ~30-60 minutes
- **Full dataset (~795,000 files)**: ~2-4 weeks (depending on network and hardware)

### Storage Requirements
- **Host storage**: ~40 GB for complete dataset in `./data/` directory
- **Container temporary**: ~5 GB for processing (automatically cleaned)
- **Raw GRIB2 files**: Downloaded and deleted automatically during processing
- **Extracted CSV data**: ~10-50 MB per day (compressed, saved to host)
- **Analysis results**: ~1-10 MB total (saved to host)

### Network Usage
- **Download per file**: ~10-50 MB
- **Total download**: ~8-40 TB for complete dataset
- **Container pulls**: One-time Docker image download (~2-3 GB)

## Monitoring and Logs

### Log Files
- Location (in container): `/srv/logs/hrrr-prate-oso-creek-YYYYMMDD.log`
- Location (on host): `./data/logs/hrrr-prate-oso-creek-YYYYMMDD.log`
- Contains: Processing progress, error messages, timing statistics

### Progress Monitoring
```bash
# Monitor current log from host (run from project root)
tail -f ./data/logs/hrrr-prate-oso-creek-$(date +%Y%m%d).log

# Monitor from within running container
docker-compose exec wgrib2 tail -f /srv/logs/hrrr-prate-oso-creek-$(date +%Y%m%d).log

# Check container logs
docker-compose logs -f wgrib2

# Check processing statistics
grep "Timer" ./data/logs/hrrr-prate-oso-creek-*.log
```

## Troubleshooting

### Common Issues

#### 1. Docker/Compose Issues
```bash
# Rebuild container if needed
docker-compose build --no-cache

# Check container status
docker-compose ps

# View container logs
docker-compose logs wgrib2
```

#### 2. Volume Mount Issues
```bash
# Ensure you're running from the project root directory
pwd  # Should show .../hrrr-deploy

# Ensure scripts and data directories exist
ls -la ./scripts
ls -la ./data

# Check .env file configuration
cat .env
```

#### 3. Disk space issues
```bash
# Monitor host disk usage
df -h

# Clean up container volumes if needed
docker-compose down -v
docker system prune -f
```

#### 4. Missing forecast files
Some forecast files may not exist in the archive. The script handles this gracefully and logs missing files.

#### 5. Container exit issues
```bash
# Run container interactively for debugging
docker-compose run --rm wgrib2 bash

```

### Performance Optimization
- Use SSD storage on host for better I/O performance
- Allocate sufficient resources to Docker
- Run on system with good internet connectivity
- Consider using AWS EC2 in us-east-1 for faster S3 access

## Data Quality Notes

### HRRR Archive Completeness
- The NOAA HRRR archive may have gaps or missing files
- Early years (2015-2016) may have fewer available forecast leads
- The script logs all missing files for quality control

### Grid Resolution
- HRRR native resolution: ~3 km
- Basin coverage: Multiple grid points within the bounding box
- Analysis provides spatial statistics across all grid points

## Citation

If using this data for research, please cite:
- NOAA HRRR Model: Benjamin et al. (2016)
- AWS Open Data Program: https://registry.opendata.aws/noaa-hrrr-pds/

## Support

For issues or questions:
1. Check log files for error messages
2. Verify environment configuration
3. Test with small date ranges first
4. Monitor disk space and network connectivity

## License

This project follows the terms of the NOAA HRRR dataset and AWS Open Data usage policies.
