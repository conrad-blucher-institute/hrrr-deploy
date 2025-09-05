# HRRR Data Extraction

Extract High-Resolution Rapid Refresh (HRRR) meteorological data for the Oso Creek / Corpus Christi basin from NOAA's AWS S3 archive.

## Quick Start

```bash
# 1. Setup
git clone git@github.com:conrad-blucher-institute/hrrr-deploy.git
cd hrrr-deploy
git checkout oso-creek-prate
cp .env.sample .env

# 2. Modify environment variables
## update RUN_COMMAND in .env to target date ranges
## if on Linux environment, update DOCKER_USER_ID & DOCKER_GROUP_ID to your username uid

# 2. Run extraction
docker compose up -d # run in the background
docker logs -f hrrr-extractor # to see the log:

# 3. Check results
ls ./data/archive/
```

## Overview

**What it extracts:**
- **Variables**: PRATE, TMP, DPT, PWAT, VUCSH, VVCSH, CAPE
- **Location**: Oso Creek basin (Lat: 27.59-27.84°N, Lon: -97.73--97.25°W)
- **Time Range**: Configurable date range (default: 2015-2021)
- **Forecast Leads**: 1-15 hours for each cycle (00-23Z)

**Output:** CSV files with meteorological data stored in `data/archive/`

## Configuration

### Checkpoint System
Resume processing from where it left off:
```bash
# Enable/disable in .env file
ENABLE_CHECKPOINT=true   # Resume from last position (default)
ENABLE_CHECKPOINT=false  # Always start from beginning of the specified date range

# Manual checkpoint (resume from specific date/hour)
echo "2020,15,12" > data/output/processing_checkpoint.txt
```

### Date Range
Edit `.env` file:
```bash
# Process specific date range (YYYYMMDD format)
RUN_COMMAND="/opt/aws-process-hrrr.sh 20200101 20201231"

# Process all available data (default)
RUN_COMMAND="/opt/aws-process-hrrr.sh"
```

### Resource Limits
Limit CPU/memory usage in `docker-compose.yml`:
```yaml
cpus: 2.0      # Limit to 2 CPU cores
mem_limit: 4g  # Limit to 4GB RAM
```

## Data Quality

### Check Missing Data
Generate reports for missing hour files:

```bash
# Check all processed dates
./scripts/check-missing-data.sh

# Check specific date range (YYYYMMDD format)
./scripts/check-missing-data.sh 20200101 20200131

# Check single day
./scripts/check-missing-data.sh 20200115 20200115
```

**Output:** CSV report in `data/report/` showing:
- Date
- Number of missing hours
- List of missing hours (00-23)

### Example Output
```csv
date,missing_hours,missing_hour_list
20200115,2,"08;09"
20200116,0,""
20200117,1,"12"
```

## Files & Directories

```
├── scripts/
│   ├── aws-process-hrrr.sh      # Main extraction script
│   └── check-missing-data.sh    # Missing data report generator
├── data/
│   ├── archive/                 # Extracted CSV files by date
│   ├── output/                  # Processing output & checkpoints
│   ├── logs/                    # Processing logs
│   └── report/                  # Data quality reports
├── docker-compose.yml           # Container configuration
└── .env                         # Environment settings
```

## Requirements

- **Docker & Docker Compose**
- **Storage**: ~100GB free space
- **Network**: Reliable internet for S3 downloads
- **Time**: 2-4 weeks for full dataset

## Output Format

CSV files contain:
- `start_time` - Forecast initialization time
- `long`, `lat` - Grid coordinates
- `valid_time` - Forecast valid time
- `[variable]_[level]` - Meteorological values

Example: `PRATE_surface`, `TMP_2_m_above_ground`, `PWAT_entire_atmosphere_considered_as_single_layer`
