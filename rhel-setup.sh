#!/usr/bin/env sh

mkdir scripts data
# By default, files created in data by container will be owned by root:root.
# Setting sgid so that files will be owned by current $user 's group
chmod g+ws data
chcon -Rt svirt_sandbox_file_t ./data/
