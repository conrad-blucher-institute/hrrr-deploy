# HRRR Data Processing Environment Configuration for Docker Compose
# Copy this file to .env and adjust paths for your host system

# HOST PATHS - Relative to project directory
# These directories will be mounted into the Docker container
HOST_SCRIPT_ABS_DIR=./scripts
HOST_DATA_ABS_DIR=./data

# DOCKER COMMAND CONFIGURATION
# Default: Run full Oso Creek extraction (Feb 19, 2015 - Mar 6, 2021)
RUN_COMMAND=/opt/aws-process-hrrr.sh

# For custom date ranges, uncomment and modify:
# RUN_COMMAND=/opt/aws-process-hrrr.sh 20150219 20150228

# For testing single day:
# RUN_COMMAND=/opt/aws-process-hrrr.sh 20200101 20200101

# For validation:
# RUN_COMMAND=/opt/validate-setup.sh


# CONTAINER PATHS (DO NOT MODIFY)
# These are set automatically in docker-compose.yml:
# HRRR_BASE_PATH=/srv
# HRRR_DOWNLOAD_PATH=/srv/download
# HRRR_OUTPUT_PATH=/srv/output  
# HRRR_ARCHIVE_PATH=/srv/archive
# HRRR_LOG_PATH=/srv/logs
