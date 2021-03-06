#!/bin/bash
#===============================================================================
#
#          FILE:  install.sh
#
#         USAGE:  ./install.sh
#
#   DESCRIPTION:  Install Quipucords server and command-line components.
#
#       OPTIONS:  -h | --help   Obtain command USAGE
#                 -e | --extra-vars  set additional variables as key=value
#===============================================================================

export PATH=$PATH:$ANSIBLE_HOME/bin
PLAYBOOKFILE="qpc_playbook.yml"
RELEASE_TAG='-e RELEASE_TAG=0.0.47'
POSTGRES_VERSION='-e POSTGRES_VERSION=9.6.10'
#TODO: Uncomment CLI_PACKAGE_VERSION when cutting a release
#CLI_PACKAGE_VERSION="-e CLI_PACKAGE_VERSION=0.0.47-ACTUAL_COPR_GIT_COMMIT"


declare -a args
args=("$*")
#TODO: you will need to make sure that the package_version is in args
#args+=("$RELEASE_TAG" "$POSTGRES_VERSION" "$CLI_PACKAGE_VERSION")
args+=("$RELEASE_TAG" "$POSTGRES_VERSION")
set -- ${args[@]}

usage() {
    cat <<EOM
    Install Quipucords server and command-line components.

    Usage:
    $(basename $0)

    Options:
    -h | --help   Obtain command USAGE
    -e | --extra-vars  set additional variables as key=value


    Extra Variables:
    * Specify if quipucords docker container should run the server without supervisord(defaults to true):
         -e use_supervisord=false
    * Specify fully-qualified directory path for local install packages (defaults to `pwd`/packages/):
         -e pkg_install_dir=/home/user/pkgs
    * Skipping install for server:
         -e install_server=false
    * Skipping install for CLI:
         -e install_cli=false
    * Specify server port (defaults to 9443):
         -e server_port=8443
    * Specify server container name (defaults to quipucords):
         -e server_name=qpc_server
    * Optionally specify the postgres db user (if not specified the default value is 'postgres'):
         -e QPC_DBMS_USER=postgres
    * Optionally specify the postgres db password (if not specified the default value is 'password')
         -e QPC_DBMS_PASSWORD=password
    * Override default server timeout for HTTP requests (if not specified the default value is 120):
         -e QPC_SERVER_TIMEOUT=120
    * Specify if installing offline
         -e install_offline=true
EOM
    exit 0
}

if [[ ($1 == "--help") ||  ($1 == "-h") ]]
then
  usage;
fi

if [ ! -f /etc/redhat-release ]; then
  echo "/etc/redhat-release not found. You need to run this on a Red Hat based OS."
  exit 1
fi

if dnf --version; then
  PKG_MGR=dnf
  if grep -q -i "27" /etc/redhat-release; then
    rpm_version="fc27"
  else
    rpm_version="fc28"
  fi
else
  PKG_MGR=yum
  if grep -q -i "release 7" /etc/redhat-release; then
    rpm_version="el7"
    if grep -q -i "Red Hat" /etc/redhat-release; then
      RHEL7=true
    fi
  else
    rpm_version="el6"
  fi
fi

offline_check() {
  echo 'Checking if required files exist for an offline installation.'
  pkg_dir='packages/'
  for i in "${args[@]}"; do
    if [[ "$i" == *"pkg_install_dir"* ]]; then
      pkg_dir="$(cut -d'=' -f2 <<<"$i")"
    fi
  done
  server_image_path="$pkg_dir/quipucords.$(cut -d'=' -f2 <<<"$RELEASE_TAG").tar.gz"
  postgres_image_path="$pkg_dir/postgres.$(cut -d'=' -f2 <<<"$POSTGRES_VERSION").tar"
  declare -a required_images=($server_image_path $postgres_image_path)
  for i in "${required_images[@]}"; do
    if [ ! -f "$i" ]; then
      echo "$i is required for an offline installation."
      unset required_images
      exit 1
    fi
  done
  unset required_images
  cli_rpm_path="$pkg_dir/qpc-$(cut -d'=' -f2 <<<"$CLI_PACKAGE_VERSION").$rpm_version.noarch.rpm"
  if [ ! -f "$cli_rpm_path" ]; then
    echo "WARNING: $cli_rpm_path was not found, but could be configured through satellite."
  fi
  echo "Checks passed continuing with installation."
}

for i in "${args[@]}"; do
  if [[ "$i" == *"offline"* ]]; then
    offline_check;
  fi
done

echo "Checking if ansible is installed..."
command -v ansible > /dev/null 2>&1

if [ $? -ne 0 ]; then
  echo "Ansible prerequisite could not be found. Trying to install ansible..."
  if [ $RHEL7 ]; then
    echo "Trying to install RHEL7 dependencies..."
    sudo subscription-manager repos --enable="rhel-7-server-extras-rpms" || true
    sudo subscription-manager repos --enable="rhel-7-server-optional-rpms" || true
  fi
  sudo "${PKG_MGR}" install -y ansible
  command -v ansible > /dev/null 2>&1
  if [ $? -ne 0]; then
    echo ""
    echo "Installation failed. Ansible prerequisite could not be installed."
    echo "Follow installation documentation for installing Ansible."
    unset args
    exit 1
  fi
fi

if [[ $EUID -ne 0 ]]
then
  echo ansible-playbook $PLAYBOOKFILE -v -K $*
  ansible-playbook $PLAYBOOKFILE -v -K $*
else
  echo ansible-playbook $PLAYBOOKFILE -v $*
  ansible-playbook $PLAYBOOKFILE -v $*
fi

if [ $? -eq 0 ]
then
  unset args
  echo "Installation complete."
else
  unset args
  echo "Installation failed. Review the install logs."
  exit 1
fi
