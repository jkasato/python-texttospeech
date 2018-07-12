#!/bin/bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -eo pipefail

cd github/python-texttospeech

# TODO(busunkim): Add logic to checkout library at latest release for periodic

# Disable buffering, so that the logs stream through.
export PYTHONUNBUFFERED=1

# Debug: show build environment
env | grep KOKORO

# Install nox
python3.6 -m pip install --upgrade --quiet nox

# Unencrypt and extract secrets
SECRETS_PASSWORD=$(cat "${KOKORO_GFILE_DIR}/secrets-password.txt")
./scripts/decrypt-secrets.sh "${SECRETS_PASSWORD}"

source ./testing/test-env.sh
export GOOGLE_APPLICATION_CREDENTIALS=$(pwd)/testing/service-account.json
export GOOGLE_CLIENT_SECRETS=$(pwd)/testing/client-secrets.json

echo -e "\n******************** TESTING PROJECTS ********************"

cd samples

# Switch to 'fail at end' to allow all tests to complete before exiting.
set +e
# Use RTN to return a non-zero value if the test fails.
RTN=0
ROOT=$(pwd)
# Find all requirements.txt in the repository (may break on whitespace).
for file in **/requirements.txt; do
    cd "$ROOT"
    # Navigate to the project folder.
    file=$(dirname "$file")
    cd "$file"

    echo "------------------------------------------------------------"
    echo "- testing $file"
    echo "------------------------------------------------------------"

    # Use nox to execute the tests for the project.
    python3.6 -m nox -s "$RUN_TESTS_SESSION"
    EXIT=$?

    # If this is a periodic build, send the test log to the Build Cop Bot.
    # See https://github.com/googleapis/repo-automation-bots/tree/master/packages/buildcop.
    if [[ $KOKORO_BUILD_ARTIFACTS_SUBDIR = *"periodic"* ]]; then
      chmod +x $KOKORO_GFILE_DIR/linux_amd64/buildcop
      $KOKORO_GFILE_DIR/linux_amd64/buildcop
    fi

    if [[ $EXIT -ne 0 ]]; then
      RTN=1
      echo -e "\n Testing failed: Nox returned a non-zero exit code. \n"
    else
      echo -e "\n Testing completed.\n"
    fi

done
cd "$ROOT"

# Workaround for Kokoro permissions issue: delete secrets
rm testing/{test-env.sh,client-secrets.json,service-account.json}

exit "$RTN"