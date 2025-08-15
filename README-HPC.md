# HRRR Data Extraction on HPC using SLURM and Singularity

This guide covers running the HRRR precipitation data extraction on High Performance Computing (HPC) systems using SLURM job scheduler and Singularity containers.

## Prerequisites

- HPC system with SLURM job scheduler
- Singularity/Apptainer installed
- Access to internet for downloading HRRR data from AWS S3
- Sufficient storage space (~40GB for complete dataset)

## Quick Start

```bash
# 1. Clone repository on HPC login node
git clone <repository-url>
cd hrrr-deploy

# 2. Setup environment
./submit-hrrr.sh setup

# 3. Test with single day
./submit-hrrr.sh test --date 20200101

# 4. Run parallel extraction (recommended)
./submit-hrrr.sh array --tasks 12

# 5. Monitor progress
./submit-hrrr.sh status

# 6. Check resume status
./submit-hrrr.sh resume
```

## Resume and Recovery

The HPC system includes robust resume capabilities:

### Check Progress
```bash
# Detailed resume status
./submit-hrrr.sh resume

# Quick job status
./submit-hrrr.sh status
```

### Resume Processing
```bash
# Resume with array job (recommended)
./submit-hrrr.sh array --tasks 12

# Resume with single job
./submit-hrrr.sh single

# The system automatically skips existing files
```

**Resume Features:**
- ✅ **Automatic file detection**: Skips existing ZIP files
- ✅ **Progress tracking**: Shows completion percentage
- ✅ **Failed task recovery**: Resubmit only failed tasks
- ✅ **No duplication**: Safe to rerun without data loss

**Recovery Strategies:**
1. **Job failure**: Resubmit with same parameters
2. **Partial completion**: New job skips completed files
3. **Network issues**: Restart automatically resumes
4. **Quota limits**: Pause and resume when space available

## Available SLURM Jobs

### 1. Test Job (`hrrr-test.slurm`)
- **Purpose**: Test with single day
- **Duration**: ~2 hours
- **Resources**: 1 CPU, 4GB RAM
- **Usage**: `./submit-hrrr.sh test --date YYYYMMDD`

### 2. Single Job (`hrrr-extract.slurm`)
- **Purpose**: Process entire dataset in one job
- **Duration**: ~72 hours (2-4 weeks)
- **Resources**: 4 CPUs, 16GB RAM
- **Usage**: `./submit-hrrr.sh single --start YYYYMMDD --end YYYYMMDD`

### 3. Array Job (`hrrr-extract-array.slurm`)
- **Purpose**: Process dataset in parallel monthly chunks
- **Duration**: ~24 hours per chunk, 72 total chunks
- **Resources**: 2 CPUs, 8GB RAM per task
- **Usage**: `./submit-hrrr.sh array --tasks 12`
- **Advantage**: Faster completion through parallelization

## Job Management

### Submit Jobs
```bash
# Test job with specific date
./submit-hrrr.sh test --date 20200101

# Single job for date range
./submit-hrrr.sh single --start 20200101 --end 20200131

# Array job with 6 parallel tasks
./submit-hrrr.sh array --tasks 6
```

### Monitor Jobs
```bash
# Check job status
./submit-hrrr.sh status

# View job logs
./submit-hrrr.sh logs JOB_ID

# View recent log files
./submit-hrrr.sh logs
```

### Manage Jobs
```bash
# Cancel specific job
./submit-hrrr.sh cancel JOB_ID

# Cancel all HRRR jobs
./submit-hrrr.sh cancel

# Clean old log files
./submit-hrrr.sh clean
```

## HPC Configuration

### Customize for Your System

Edit the SLURM scripts to match your HPC environment:

```bash
# Edit partition name
sed -i 's/#SBATCH --partition=compute/#SBATCH --partition=your_partition/' *.slurm

# Edit email notifications
sed -i 's/your.email@example.com/your.actual@email.com/' *.slurm

# Adjust resource requirements
# Edit --mem, --cpus-per-task, --time as needed
```

### Module Loading

Update the module loading section in SLURM scripts:

```bash
# Example for different HPC systems:
# module load singularity          # Generic
# module load apptainer           # NERSC, some systems
# module load singularity/3.8.0   # Specific version
```

## Performance Optimization

### Array Job Strategy (Recommended)
- Processes 72 monthly chunks in parallel
- Each chunk: ~24 hours, 2 CPUs, 8GB RAM
- Total time: ~1-2 weeks depending on queue
- Automatic cleanup and result consolidation

### Resource Tuning
```bash
# For I/O intensive workloads
#SBATCH --mem=16G          # More memory for data buffering

# For faster storage systems
#SBATCH --time=12:00:00    # Reduce time limit

# For slower networks
#SBATCH --time=48:00:00    # Increase time limit
```

### Storage Considerations
- Use fast scratch storage if available
- Set `DATA_DIR` to scratch filesystem
- Copy final results to permanent storage

```bash
# Example for scratch storage
export DATA_DIR="/scratch/$USER/hrrr-data"
mkdir -p "$DATA_DIR"
```

## File Organization

```
hrrr-deploy/
├── *.slurm                 # SLURM job scripts
├── submit-hrrr.sh         # Job management script
├── scripts/               # Processing scripts
├── logs/                  # SLURM job logs
└── data/                  # Extracted data
    ├── archive/           # Final compressed CSV files
    ├── logs/              # Application logs
    └── task_*/            # Temporary task directories (array jobs)
```

## Output Data

### File Naming
- Single job: `YYYYMMDD-HH-prate-raw.zip`
- Array jobs: Same naming, automatically consolidated

### Data Format
Each ZIP contains CSV with columns:
```csv
datetime,forecast_lead,lat,lon,prate_kg_m2_s
2020-01-01T00:00:00Z,01,27.625,-97.375,0.000123
```

## Troubleshooting

### Common Issues

#### 1. Singularity Image Pull Failures
```bash
# Pre-pull image on login node
singularity pull docker://sondngyn/wgrib2:latest
# Update scripts to use local image
```

#### 2. Storage Quota Issues
```bash
# Monitor usage
df -h $HOME
df -h /scratch/$USER

# Clean temporary files
./submit-hrrr.sh clean
```

#### 3. Network Timeouts
```bash
# Increase timeout in SLURM scripts
#SBATCH --time=48:00:00

# Use fewer parallel downloads
# Edit aws-process-hrrr.sh if needed
```

#### 4. Job Array Issues
```bash
# Check individual task logs
ls logs/hrrr-array-*_*.out

# Resubmit failed tasks
# Find failed task IDs and resubmit manually
```

### Monitoring Progress

#### Check Data Volume
```bash
# Total files extracted
find data/archive -name "*.zip" | wc -l

# Data size
du -sh data/archive

# Progress by month
ls data/archive | cut -c1-6 | sort | uniq -c
```

#### Log Analysis
```bash
# Check for errors
grep -i error logs/*.err

# Processing statistics
grep "Timer" data/logs/*.log

# Download speeds
grep "downloaded in" data/logs/*.log
```

## System-Specific Examples

### TACC Stampede3
```bash
module load tacc-singularity
#SBATCH --partition=skx-normal
#SBATCH --time=48:00:00
```

### NERSC Perlmutter
```bash
module load cray-python
#SBATCH --constraint=cpu
#SBATCH --qos=regular
```

### Generic SLURM
```bash
module load singularity
#SBATCH --partition=compute
#SBATCH --time=24:00:00
```

## Support

For issues specific to:
- **SLURM**: Contact your HPC support team
- **Singularity**: Check system documentation
- **HRRR extraction**: Check application logs in `data/logs/`

Remember to customize the SLURM scripts for your specific HPC environment before submitting jobs!
