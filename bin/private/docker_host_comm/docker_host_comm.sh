#!/bin/bash
#set -x


ABSPATH=$(readlink -f $0)
ABSDIR=$(dirname $ABSPATH)


BASE_PATH=$ABSDIR/../../..

PIPE=$BASE_PATH/var/pipe_send_to_server_command


cd $BASE_PATH

if [[ ! -p "$PIPE" ]]; then
  mkfifo "$PIPE"
  chmod ugo+rw $PIPE
fi


echo "Iniciando servidor $(basename $0)"

while true
do
    if read line <$PIPE; then
        if [[ "$line" == '#_#_#_# EXIT #_#_#_#' ]]; then
            exit 0
        fi
        
				echo $line

	      git pull

				$BASE_PATH/bin/private/docker_host_comm/exec_command.sh $line  &


    else
			echo "Esperando...."
    fi
done

echo "Terminado servidor"
