#!/usr/bin/env python3

import json
import subprocess

print('<<<local>>>')

try:

  response = subprocess.check_output(['ha', 'supervisor', 'info', '--raw-json'])
  data = json.loads(response)

except:
  exit(0)

try:
  if data['data']['healthy'] == True:
    # OK
    code='0'
    nicestatus='Healthy'
    perf='healthy=1 '
  else:
    # CRIT
    code='2'
    nicestatus='Unhealthy'
    perf='healthy=0 '
except:
  # Unknown
  code='3'
  nicestatus="Unknown"
  perf=' - '
print(code + ' "Supervisor Healthy" ' + perf + nicestatus)

try:
  if data['data']['supported'] == True:
    # OK
    code='0'
    nicestatus='Supported'
    perf='supported=1 '
  else:
    # CRIT
    code='2'
    nicestatus='Unsupported'
    perf='supported=0 '
except:
  # Unknown
  code='3'
  nicestatus="Unknown"
  perf=' - '
print(code + ' "Supervisor Supported" ' + perf + nicestatus)