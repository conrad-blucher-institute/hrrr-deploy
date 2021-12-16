### <b><u>DEPLOYMENT GUIDE</u></b>
________________
_____________________
#### <u>LOCAL MACHINE</u>
1. Make .env from .env.dist
2. Change environment vars in .env
3. Copy [aws-process-hrrr.sh](https://github.com/conrad-blucher-institute/hrrr-project/blob/main/aws-process-hrrr.sh) file from `hrrr-project` repo to the directory where the script is being run (at `HOST_SCRIPT_ABS_DIR` env variable)
4. `docker-compose up`

__________