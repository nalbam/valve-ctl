#!/bin/bash

OS_NAME="$(uname | awk '{print tolower($0)}')"

THIS_VERSION=v0.0.0

CMD=$1
SUB=$2

NAME=
VERSION=0.0.0

SECRET=
PACKAGE=

NAMESPACE=
CLUSTER=

BASE_DOMAIN=
JENKINS=
REGISTRY=
CHARTMUSEUM=
SONARQUBE=
NEXUS=

CONFIG=${HOME}/.valve-tee

touch ${CONFIG} && . ${CONFIG}

for v in "$@"; do
    case ${v} in
    --name=*)
        NAME="${v#*=}"
        shift
        ;;
    --version=*)
        VERSION="${v#*=}"
        shift
        ;;
    --secret=*)
        SECRET="${v#*=}"
        shift
        ;;
    --package=*)
        PACKAGE="${v#*=}"
        shift
        ;;
    --namespace=*)
        NAMESPACE="${v#*=}"
        shift
        ;;
    --cluster=*)
        CLUSTER="${v#*=}"
        shift
        ;;
    --this=*)
        THIS_VERSION="${v#*=}"
        shift
        ;;
    *)
        shift
        ;;
    esac
done

################################################################################

command -v tput > /dev/null || TPUT=false

_bar() {
    _echo "================================================================================"
}

_echo() {
    if [ -z ${TPUT} ] && [ ! -z $2 ]; then
        echo -e "$(tput setaf $2)$1$(tput sgr0)"
    else
        echo -e "$1"
    fi
}

_read() {
    if [ -z ${TPUT} ]; then
        read -p "$(tput setaf 6)$1$(tput sgr0)" ANSWER
    else
        read -p "$1" ANSWER
    fi
}

_result() {
    _echo "# $@" 4
}

_command() {
    _echo "$ $@" 3
}

_success() {
    _echo "+ $@" 2
    exit 0
}

_error() {
    _echo "- $@" 1
    exit 1
}

_replace() {
    if [ "${OS_NAME}" == "darwin" ]; then
        sed -i "" -e "$1" $2
    else
        sed -i -e "$1" $2
    fi
}

_logo() {
    #figlet valve tee
    _bar
    _echo "             _             _             "
    _echo " __   ____ _| |_   _____  | |_ ___  ___  "
    _echo " \ \ / / _' | \ \ / / _ \ | __/ _ \/ _ \ "
    _echo "  \ V / (_| | |\ V /  __/ | ||  __/  __/ "
    _echo "   \_/ \__,_|_| \_/ \___|  \__\___|\___|  ${THIS_VERSION}"
    _bar
}

_usage() {
    _logo
    _echo " Usage: $0 {create|up|tools|update|version}"
    _bar
    _error
}

################################################################################

_run() {
    case ${CMD} in
        i|init)
            _draft_init
            ;;
        c|create|gen)
            _draft_create
            ;;
        u|up)
            _draft_up
            ;;
        tools)
            _tools
            ;;
        update)
            _update
            ;;
        v|version)
            _version
            ;;
        *)
            _usage
    esac
}

_tools() {
    curl -sL repo.opsnow.io/valve-tee/tools | bash
    exit 0
}

_update() {
    curl -sL repo.opsnow.io/valve-tee/install | bash
    exit 0
}

_version() {
    _success ${THIS_VERSION} 2
}

_config_save() {
    echo "# tee config" > ${CONFIG}
    echo "SECRET=${SECRET}" >> ${CONFIG}
    echo "PACKAGE=${PACKAGE}" >> ${CONFIG}
    echo "NAMESPACE=${NAMESPACE}" >> ${CONFIG}
    echo "CLUSTER=${CLUSTER}" >> ${CONFIG}
    echo "BASE_DOMAIN=${BASE_DOMAIN}" >> ${CONFIG}
    echo "JENKINS=${JENKINS}" >> ${CONFIG}
    echo "REGISTRY=${REGISTRY}" >> ${CONFIG}
    echo "CHARTMUSEUM=${CHARTMUSEUM}" >> ${CONFIG}
    echo "SONARQUBE=${SONARQUBE}" >> ${CONFIG}
    echo "NEXUS=${NEXUS}" >> ${CONFIG}
}

_helm_init() {
    _command "helm init"
    helm init

    # TODO wait tiller

    _command "helm version"
    helm version
}

_draft_init() {
    _helm_init

    _command "draft init"
    draft init

    _command "draft version"
    draft version

    NAMESPACE="kube-public"

    # nginx-ingress
    COUNT=$(helm ls nginx-ingress | wc -l | xargs)
    if [ "x${COUNT}" == "x0" ]; then
        curl -sL https://raw.githubusercontent.com/opsnow-tools/valve-tee/master/charts/nginx-ingress.yaml > /tmp/nginx-ingress.yaml

        _command "helm upgrade --install nginx-ingress stable/nginx-ingress"
        helm upgrade --install nginx-ingress stable/nginx-ingress --namespace ${NAMESPACE} -f /tmp/nginx-ingress.yaml
    fi

    # docker-registry
    COUNT=$(helm ls docker-registry | wc -l | xargs)
    if [ "x${COUNT}" == "x0" ]; then
        curl -sL https://raw.githubusercontent.com/opsnow-tools/valve-tee/master/charts/docker-registry.yaml > /tmp/docker-registry.yaml

        _command "helm upgrade --install docker-registry stable/docker-registry"
        helm upgrade --install docker-registry stable/docker-registry --namespace ${NAMESPACE} -f /tmp/docker-registry.yaml
    fi

    # TODO wait infra

    REGISTRY=
    REGISTRY="docker-registry.127.0.0.1.nip.io:30500"
    # curl -sL docker-registry.127.0.0.1.nip.io:30500/v2/_catalog

    draft config set disable-push-warning 1

    # registry
    if [ -z ${REGISTRY} ]; then
        _command "draft config unset registry"
        draft config unset registry
    else
        _command "draft config set registry ${REGISTRY}"
        draft config set registry ${REGISTRY}
    fi

    _config_save
}

_draft_create() {
    _result "draft package version: ${THIS_VERSION}"

    echo
    _read "Do you really want to apply? (YES/[no]) : "
    echo

    if [ "${ANSWER}" != "YES" ]; then
        exit 0
    fi

    DIST=/tmp/tee-draft-${THIS_VERSION}
    LIST=/tmp/tee-draft-ls

    if [ ! -d ${DIST} ]; then
        mkdir -p ${DIST}

        # download
        pushd ${DIST}
        curl -sL https://github.com/opsnow-tools/valve-tee/releases/download/${THIS_VERSION}/draft.tar.gz | tar xz
        popd

        echo
        _result "draft package downloaded."
        echo
    fi

    # find all
    ls ${DIST} > ${LIST}

    IDX=0
    while read VAL; do
        IDX=$(( ${IDX} + 1 ))
        printf "%3s %s\n" "$IDX" "$VAL";
    done < ${LIST}

    echo
    _read "Please select a project type. (1-5) : "
    echo

    SELECTED=
    if [ -z ${ANSWER} ]; then
        _error
    fi
    TEST='^[0-9]+$'
    if ! [[ ${ANSWER} =~ ${TEST} ]]; then
        _error
    fi
    SELECTED=$(sed -n ${ANSWER}p ${LIST})

    _result "${SELECTED}"

    rm -rf charts

    # copy
    cp -rf ${DIST}/${SELECTED}/charts charts
    cp -rf ${DIST}/${SELECTED}/dockerignore .dockerignore
    cp -rf ${DIST}/${SELECTED}/draftignore .draftignore
    cp -rf ${DIST}/${SELECTED}/Dockerfile Dockerfile
    cp -rf ${DIST}/${SELECTED}/Jenkinsfile Jenkinsfile
    cp -rf ${DIST}/${SELECTED}/draft.toml draft.toml

    # Jenkinsfile IMAGE_NAME
    DEFAULT=$(basename $(pwd))
    _chart_replace "Jenkinsfile" "def IMAGE_NAME" "${DEFAULT}"
    IMAGE_NAME="${REPLACE_VAL}"

    # draft.toml NAME
    _replace "s|NAME|${IMAGE_NAME}|" draft.toml

    # charts/acme/Chart.yaml
    _replace "s|name: .*|name: ${IMAGE_NAME}|" charts/acme/Chart.yaml

    # charts/acme/values.yaml
    _replace "s|repository: .*|repository: ${IMAGE_NAME}|" charts/acme/values.yaml

    # charts name
    mv charts/acme charts/${IMAGE_NAME}

    # Jenkinsfile REPOSITORY_URL
    DEFAULT=
    if [ -d .git ]; then
        DEFAULT=$(git remote -v | head -1 | awk '{print $2}')
    fi
    _chart_replace "Jenkinsfile" "def REPOSITORY_URL" "${DEFAULT}"
    REPOSITORY_URL="${REPLACE_VAL}"

    # Jenkinsfile REPOSITORY_SECRET
    _chart_replace "Jenkinsfile" "def REPOSITORY_SECRET" "${SECRET}"
    SECRET="${REPLACE_VAL}"

    # Jenkinsfile CLUSTER
    _chart_replace "Jenkinsfile" "def CLUSTER" "${CLUSTER}"
    CLUSTER="${REPLACE_VAL}"

    # Jenkinsfile BASE_DOMAIN
    _chart_replace "Jenkinsfile" "def BASE_DOMAIN" "${BASE_DOMAIN}"
    BASE_DOMAIN="${REPLACE_VAL}"

    _config_save
}

_draft_up() {
    _draft_init

    if [ ! -f draft.toml ]; then
        _error "Not found draft.toml"
    fi

    NAME="$(cat draft.toml | grep "name =" | cut -d'"' -f2 | xargs)"

    NAMESPACE="development"

    # charts/acme/values.yaml
    if [ -z ${REGISTRY} ]; then
        _replace "s|repository: .*|repository: ${NAME}|" charts/${NAME}/values.yaml
    else
        _replace "s|repository: .*|repository: ${REGISTRY}/${NAME}|" charts/${NAME}/values.yaml
    fi

    _command "draft up -e ${NAMESPACE}"
	draft up -e ${NAMESPACE}

    _command "helm ls"
    helm ls

    _command "kubectl get pod,svc,ing -n ${NAMESPACE}"
    kubectl get pod,svc,ing -n ${NAMESPACE}
}

_draft_delete() {
    # _draft_init

    _command "helm ls --all"
    helm ls --all

    _read "Enter chart name : "

    if [ ! -z ${ANSWER} ]; then
        _command "helm delete --purge ${ANSWER}"
        helm delete --purge ${ANSWER}
    fi
}

_chart_replace() {
    REPLACE_FILE=$1
    REPLACE_KEY=$2
    DEFAULT_VAL=$3
    REPLACE_TYPE=$4

    echo

    if [ "${DEFAULT_VAL}" == "" ]; then
        _read "${REPLACE_KEY} : "
    else
        _read "${REPLACE_KEY} [${DEFAULT_VAL}] : "
    fi

    if [ -z ${ANSWER} ]; then
        REPLACE_VAL=${DEFAULT_VAL}
    else
        REPLACE_VAL=${ANSWER}
    fi

    if [ "${REPLACE_TYPE}" == "yaml" ]; then
        _command "sed -i -e s|${REPLACE_KEY}: .*|${REPLACE_KEY}: ${REPLACE_VAL}| ${REPLACE_FILE}"
        _replace "s|${REPLACE_KEY}: .*|${REPLACE_KEY}: ${REPLACE_VAL}|" ${REPLACE_FILE}
    else
        _command "sed -i -e s|${REPLACE_KEY} = .*|${REPLACE_KEY} = ${REPLACE_VAL}| ${REPLACE_FILE}"
        _replace "s|${REPLACE_KEY} = .*|${REPLACE_KEY} = \"${REPLACE_VAL}\"|" ${REPLACE_FILE}
    fi
}

_run

_success "done."
