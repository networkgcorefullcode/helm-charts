#!/bin/sh

# Copyright 2024-present Intel Corporation
# Copyright 2020-present Open Networking Foundation
#
# SPDX-License-Identifier: Apache-2.0

set -x

{{- if .Values.config.coreDump.enabled }}
cp /usr/local/bin/webconsole /tmp/coredump/
{{- end }}

CFGPATH=/home
FILENAME=webuicfg.yaml
# copy config file from configmap (/opt) to a general directory (/home)
cp /opt/$FILENAME $CFGPATH/$FILENAME
cat $CFGPATH/$FILENAME
echo ""

GOTRACEBACK=crash webconsole -cfg $CFGPATH/$FILENAME

if [ $? -ne 0 ]; then
	echo "Error: webconsole command failed."
    GOTRACEBACK=crash webconsole-ui -cfg $CFGPATH/$FILENAME
fi