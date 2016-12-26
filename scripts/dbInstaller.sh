#!/bin/bash
set -e

chown -R oracle:dba /u01/app/oracle

if [ "$(ls -A /tmp/oraconfig)" ]; then 
    chown -R oracle:dba /tmp/oraconfig
fi

rm -f /u01/app/oracle/product
ln -s /u01/app/oracle-product /u01/app/oracle/product

/u01/app/oraInventory/orainstRoot.sh > /dev/null 2>&1
echo | /u01/app/oracle/product/12.1.0/xe/root.sh > /dev/null 2>&1 || true


case "$1" in
    '')
        echo "Configuring database"
        echo "============================================================================="

        if [ "$(ls -A /u01/app/oracle/oradata)" ]; then
            echo "Found existing /u01/app/oracle/oradata Using them instead of initial database"
			echo "XE:$ORACLE_HOME:N" >> /etc/oratab
			chown oracle:dba /etc/oratab
			chown 664 /etc/oratab
			rm -rf /u01/app/oracle-product/12.1.0/xe/dbs
			ln -s /u01/app/oracle/dbs /u01/app/oracle-product/12.1.0/xe/dbs
			#Startup Database
			su oracle -c "/u01/app/oracle/product/12.1.0/xe/bin/tnslsnr &"
			su oracle -c 'echo startup\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'
        else
            echo "Database not initialized. Initializing database."
            #export IMPORT_FROM_VOLUME=true

            if [ -z "$CHARACTER_SET" ]; then
                export CHARACTER_SET="AL32UTF8"
            fi

            mv /u01/app/oracle-product/12.1.0/xe/dbs /u01/app/oracle/dbs
            ln -s /u01/app/oracle/dbs /u01/app/oracle-product/12.1.0/xe/dbs
            
            echo "Starting tnslsnr"
            su oracle -c "/u01/app/oracle/product/12.1.0/xe/bin/tnslsnr &"
            #create DB for SID: xe
            su oracle -c "$ORACLE_HOME/bin/dbca -silent -createDatabase -templateName General_Purpose.dbc -gdbname xe.oracle.docker -sid xe -responseFile NO_VALUE -characterSet $CHARACTER_SET -totalMemory $DBCA_TOTAL_MEMORY -emConfiguration LOCAL -pdbAdminPassword oracle -sysPassword oracle -systemPassword oracle"

            echo "Configuring Apex console"
            cd $ORACLE_HOME/apex
            su oracle -c 'echo -e "0Racle$\n8080" | $ORACLE_HOME/bin/sqlplus -S / as sysdba @apxconf > /dev/null'
            su oracle -c 'echo -e "${ORACLE_HOME}\n\n" | $ORACLE_HOME/bin/sqlplus -S / as sysdba @apex_epg_config_core.sql > /dev/null'
            su oracle -c 'echo -e "ALTER USER ANONYMOUS ACCOUNT UNLOCK;" | $ORACLE_HOME/bin/sqlplus -S / as sysdba > /dev/null'
            echo "Database initialized. Please visit http://#containeer:8080/em http://#containeer:8080/apex for extra configuration if needed"
        
            if [ -f /tmp/oraconfig/geneva_admin_v9.dmp ]; then
                echo "Creating Geneva_admin"
                su oracle -c "NLS_LANG=.$CHARACTER_SET /u01/app/oracle/product/12.1.0/xe/bin/sqlplus -S / as sysdba @/tmp/oraconfig/geneva.sql"
                echo "Creating tnsnames.ora"
                su oracle -c "cp /tmp/oraconfig/tnsnames.ora /u01/app/oracle-product/12.1.0/xe/network/admin/"
                su oracle -c "$ORACLE_HOME/bin/lsnrctl reload"
                echo "Extracting dump file"
                su oracle -c "$ORACLE_HOME/bin/imp system/oracle@xe fromuser=geneva_admin touser=geneva_admin file=/tmp/oraconfig/geneva_admin_v9.dmp grants=Y constraints=N log=/u01/app/oracle/geneva_admin.log"
            fi
        fi

        if [ $WEB_CONSOLE == "true" ]; then
			echo 'Starting web management console'
			su oracle -c 'echo EXEC DBMS_XDB.sethttpport\(8080\)\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'
		else
			echo 'Disabling web management console'
			su oracle -c 'echo EXEC DBMS_XDB.sethttpport\(0\)\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'
		fi

		if [ $IMPORT_FROM_VOLUME ]; then
			echo "Starting import from '/docker-entrypoint-initdb.d':"

			for f in /docker-entrypoint-initdb.d/*; do
				echo "found file /docker-entrypoint-initdb.d/$f"
				case "$f" in
					*.sh)     echo "[IMPORT] $0: running $f"; . "$f" ;;
					*.sql)    echo "[IMPORT] $0: running $f"; echo "exit" | su oracle -c "NLS_LANG=.$CHARACTER_SET /u01/app/oracle/product/12.1.0/xe/bin/sqlplus -S / as sysdba @$f"; echo ;;
					*)        echo "[IMPORT] $0: ignoring $f" ;;
				esac
				echo
			done

			echo "Import finished"
			echo
		else
			echo "[IMPORT] Not a first start, SKIPPING Import from Volume '/docker-entrypoint-initdb.d'"
			echo "[IMPORT] If you want to enable import at any state - add 'IMPORT_FROM_VOLUME=true' variable"
		fi

        echo "Seting path" 
        export PATH=$PATH:$ORACLE_HOME/bin
        export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$ORACLE_HOME/lib

        echo "Database is available for connections."

		## Workaround for graceful shutdown.
		while [ "$END" == '' ]; do
            sleep 1
			trap "su oracle -c 'echo shutdown immediate\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'" INT TERM
		done
		;;
    *)
        echo "!!!Database is not configured, runt /tmp/dbInstaller.sh to configure it"
        echo "============================================================================="
        ;;
esac