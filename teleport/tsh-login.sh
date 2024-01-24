#!/usr/bin/env bash

declare -A OPTS

# check to see if this file is being run or sourced from another script
_is_sourced() {
	# https://unix.stackexchange.com/a/215279
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}

function _usage() {
  echo -e "tsh-login proxy\n"
  echo -e "Usage:"
  echo -e "  bash $0 [OPTIONS...]\n"
  echo -e "Options:"
  echo -e "  -d, --database\t\t\tThe database link"
  echo -e "  -e, --entry\t\t\tThe entry name"
  echo -e "  -v, --version\t\t\tShow version information and exit"
  echo -e "  -h, --help\t\t\tShow help"
  echo ""

  exit
}

cmdline() {
    local arg

    for arg
    do
        local delim=""
        case "$arg" in
            --database) args="${args}-d ";;
            --entry) args="${args}-e ";;
            --teleport-proxy) args="${args}-P ";;
            --teleport-auth) args="${args}-A ";;
            --teleport-user) args="${args}-U ";;
            --teleport-cluster) args="${args}-C ";;
            --help) args="${args}-h ";;
            *) [[ "${arg:0:1}" == "-" ]] || delim="\""
                args="${args}${delim}${arg}${delim} ";;
        esac
    done

    eval set -- "$args"

    while getopts "d:e:P:A:U:C:h" OPTION
    do
      case "$OPTION" in
      d)
        OPTS[database]="$OPTARG"
        ;;
      e)
        OPTS[entry]="$OPTARG"
        ;;
      P)
        OPTS[teleport_proxy]="$OPTARG"
        ;;
      A)
        OPTS[teleport_auth]="$OPTARG"
        ;;
      U)
        OPTS[teleport_user]="$OPTARG"
        ;;
      C)
        OPTS[teleport_cluster]="$OPTARG"
        ;;
      *)
        exit 1
      esac
    done

    return 0
}

keepass_get_password() {
  local PASS
  PASS="$(zenity --password)"
  readonly PASS

  echo "$PASS"
}

tsh_login() {
  local PASS
    PASS="$(keepass_get_password)"
    readonly PASS

    local KEE_DATA KEE_RC
    KEE_DATA=$(echo "$PASS" | keepassxc-cli show -a Password -s -t "${OPTS[database]}" "${OPTS[entry]}" 2>&1)
    KEE_RC=$?
    readonly KEE_DATA
    readonly KEE_RC

    if [[ "$KEE_RC" -ne 0 ]]; then
      echo "$KEE_DATA" | tail -n +2
      exit 1
    fi

    local KEE_PASS KEE_TOTP
    local i=0
    while IFS= read -r line; do
      [[ "$i" -eq 1 ]] && KEE_PASS="$line"
      [[ "$i" -eq 2 ]] && KEE_TOTP="$line"

      (( i++ ))
    done <<< "$KEE_DATA"

    /usr/bin/expect << EOF
      set timeout -1
      log_user 1

      spawn tsh login --proxy=${OPTS[teleport_proxy]} --auth=${OPTS[teleport_auth]} --user=${OPTS[teleport_user]} ${OPTS[teleport_cluster]}

      expect {
        "Enter password for Teleport user" {
          send -- "$KEE_PASS\n"
          exp_continue
        }

        "Enter your OTP token" {
          send -- "$KEE_TOTP\n"
          exp_continue
        }

        "ERROR:" {
           expect eof
           exit 1
        }

        eof { wait }
      }
EOF
}

_main() {
  cmdline "$@"

  tsh_login
}

if ! _is_sourced; then
	_main "$@"
fi