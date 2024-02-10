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
  echo -e "  bash $0 [OPTIONS...] -- commands\n"
  echo -e "Options:"
  echo -e "  -d, --database\t\t\tThe database link"
  echo -e "  -e, --entry\t\t\tThe entry name"
  echo -e "  -a, --auto\t\t\tAuto complete command if string contain '\' (Like: tsh --user=\\\UserName --proxy=\\\tsh-proxy ...)"
  echo -e "  -v, --version\t\t\tShow version information and exit"
  echo -e "  -h, --help\t\t\tShow help"
  echo ""

  exit
}

cmdline() {
    local arg
    local exec_arg

    for arg
    do
        local delim=""
        case "$arg" in
            --database) args="${args}-d ";;
            --entry) args="${args}-e ";;
            --auto) args="${args}-a ";;
            --help) args="${args}-h ";;
            --) exec_arg="$arg ";;
            *)
              [[ "${arg:0:1}" == "-" ]] || delim="\""
              if [[ -z "$exec_arg" ]]; then
                args="${args}${delim}${arg}${delim} "
              else
                exec_arg="${exec_arg}${delim}${arg}${delim} "
              fi
              ;;
        esac
    done

    eval set -- "$args"
    while getopts "d:e:ah" OPTION
    do
      case "$OPTION" in
      h)
        _usage
        ;;
      d)
        OPTS[database]="$OPTARG"
        ;;
      e)
        OPTS[entry]="$OPTARG"
        ;;
      a)
        OPTS[auto]=1
        ;;
      *)
        exit 1
      esac
    done

    if [[ -z "$exec_arg" ]]; then
      echo "[ERR] Please add your command after \"--\""
      exit 1
    fi

    OPTS[exec]="${exec_arg:3:-1}"

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
  KEE_DATA=$(echo "$PASS" | keepassxc-cli show -s --all -t "${OPTS[database]}" "${OPTS[entry]}" 2>&1)
  KEE_RC=$?
  readonly KEE_DATA
  readonly KEE_RC

  if [[ "$KEE_RC" -ne 0 ]]; then
    echo "$KEE_DATA" | tail -n +2
    exit 1
  fi

  PARSE_RESULT=$(awk -v kee_data="$KEE_DATA" -v arg_data="${OPTS[exec]//'\'/"\\\\"}" '
  function rec_wrap(str) {
    matches = ""
    return rec_func(str)
  }
  function rec_func(str2) {
    where = match(str2, /\\[a-zA-Z][a-zA-Z0-9_-]+/)
    if(where != 0) {
        matches=(matches substr(str2, RSTART, RLENGTH) " ")
        rec_func(substr(str2, RSTART+RLENGTH, length(str2)))
    }
    return matches
  }
  { totp = "" }
  BEGIN {
    split(kee_data, kee_arr, "\n")
    for (i = 2; i <= length(kee_arr); i++) {
      if (i == length(kee_arr)) {
        totp = kee_arr[i]
        break
      }

      split(kee_arr[i], tmp, ": ")
      data[tmp[1]] = tmp[2]
    }

    cmd = arg_data
    split(rec_wrap(arg_data), arg_arr, " ")
    for (i = 1; i <= length(arg_arr); i++) {
      key = substr(arg_arr[i], 2)
      value = data[key]
      if (value == "") {
        continue
      }

      gsub("\\" arg_arr[i] , value, cmd)
    }

    print data["Password"]
    print totp
    print cmd
    exit
  }
  ')
  readonly PARSE_RESULT

  local KEE_PASS KEE_TOTP KEE_CMD
  local i=0
  while IFS= read -r line; do
    [[ "$i" -eq 0 ]] && KEE_PASS="$line"
    [[ "$i" -eq 1 ]] && KEE_TOTP="$line"
    [[ "$i" -eq 2 ]] && KEE_CMD="$line"

    (( i++ ))
  done <<< "$PARSE_RESULT"

  local EXEC
  if [[ "${OPTS[auto]}" -eq 1 ]]; then
    EXEC="${KEE_CMD}"
  else
    EXEC="${OPTS[exec]}"
  fi
  readonly EXEC

  /usr/bin/expect << EOF
    set timeout -1
    log_user 1

    spawn $EXEC

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