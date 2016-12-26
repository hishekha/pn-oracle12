FROM sath89/oracle-12c-base

MAINTAINER hshekhar<himanshu.shekhar.in@gmail.com>

LABEL description="Oracle 12c based image"

ENV WEB_CONSOLE true
ENV DBCA_TOTAL_MEMORY 1024
ENV ORACLE_HOME	/u01/app/oracle/product/12.1.0/xe

ADD scripts/dbInstaller.sh /tmp/
RUN chmod +x /tmp/dbInstaller.sh

ADD data/geneva_admin_v9.dmp /tmp/oraconfig/
ADD config/tnsnames.ora /tmp/oraconfig
ADD config/geneva.sql /tmp/oraconfig

EXPOSE 1521
EXPOSE 8080

VOLUME ["/u01/app/oracle"]

ENTRYPOINT ["/tmp/dbInstaller.sh"]
CMD [""]