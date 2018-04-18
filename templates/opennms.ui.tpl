#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

hostname="${hostname}"
domainname="${domainname}"
redis_server="${redis_server}"
postgres_onms_url="${postgres_onms_url}"
postgres_server="${postgres_server}"
cassandra_servers="${cassandra_servers}"
webui_endpoint="${webui_endpoint}"
elastic_url="${elastic_url}"
elastic_user="${elastic_user}"
elastic_password="${elastic_password}"
use_30sec_frequency="${use_30sec_frequency}"

echo "### Configuring Hostname and Domain..."

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring OpenNMS..."

opennms_home=/opt/opennms
opennms_etc=$opennms_home/etc

# Database connections
postgres_tmpl_url=`echo $postgres_onms_url | sed 's|/opennms|/template1|'`
cat <<EOF > $opennms_etc/opennms-datasources.xml
<?xml version="1.0" encoding="UTF-8"?>
<datasource-configuration xmlns:this="http://xmlns.opennms.org/xsd/config/opennms-datasources"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://xmlns.opennms.org/xsd/config/opennms-datasources
  http://www.opennms.org/xsd/config/opennms-datasources.xsd ">

  <connection-pool factory="org.opennms.core.db.HikariCPConnectionFactory"
    idleTimeout="600"
    loginTimeout="3"
    minPool="50"
    maxPool="50"
    maxSize="50" />

  <jdbc-data-source name="opennms"
                    database-name="opennms"
                    class-name="org.postgresql.Driver"
                    url="$postgres_onms_url"
                    user-name="opennms"
                    password="opennms">
    <param name="connectionTimeout" value="0"/>
    <param name="maxLifetime" value="600000"/>
  </jdbc-data-source>

  <jdbc-data-source name="opennms-admin"
                    database-name="template1"
                    class-name="org.postgresql.Driver"
                    url="$postgres_tmpl_url"
                    user-name="postgres"
                    password="postgres" />
</datasource-configuration>
EOF

# JVM Settings
total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi
jmxport=18980
cat <<EOF > $opennms_etc/opennms.conf
START_TIMEOUT=0
JAVA_HEAP_SIZE=$mem_in_mb
MAXIMUM_FILE_DESCRIPTORS=204800

ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UseG1GC -XX:+UseStringDeduplication"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -d64 -XX:+PrintGCTimeStamps -XX:+PrintGCDetails"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Xloggc:$opennms_home/logs/gc.log"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -XX:+UnlockCommercialFeatures -XX:+FlightRecorder"

# Configure Remote JMX
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.port=$jmxport"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.rmi.port=$jmxport"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.local.only=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.ssl=false"
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dcom.sun.management.jmxremote.authenticate=true"

# Listen on all interfaces
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Dopennms.poller.server.serverHost=0.0.0.0"

# Accept remote RMI connections on this interface
ADDITIONAL_MANAGER_OPTIONS="\$ADDITIONAL_MANAGER_OPTIONS -Djava.rmi.server.hostname=$hostname"
EOF

# JMX Groups
cat <<EOF > $opennms_etc/jmxremote.access
admin readwrite
jmx   readonly
EOF

# External Cassandra
newts_cfg=$opennms_etc/opennms.properties.d/newts.properties
cat <<EOF > $newts_cfg
org.opennms.timeseries.strategy=newts
org.opennms.newts.config.hostname=$cassandra_servers
org.opennms.newts.config.keyspace=newts
org.opennms.newts.config.port=9042
org.opennms.newts.config.read_consistency=ONE
EOF
if [[ "$redis_server" != "" ]]; then
  cat <<EOF >> $newts_cfg
org.opennms.newts.config.cache.redis_hostname=$redis_server
org.opennms.newts.config.cache.redis_port=6379
EOF
fi
if [ "$use_30sec_frequency" == "true" ]; then
  cat <<EOF >> $newts_cfg
org.opennms.newts.query.minimum_step=30000
org.opennms.newts.query.heartbeat=45000
EOF
fi

# External Elasticsearch for Flows
cat <<EOF > $opennms_etc/org.opennms.features.flows.persistence.elastic.cfg
elasticUrl=$elastic_url
elasticGlobalUser=$elastic_user
elasticGlobalPassword=$elastic_password
EOF

# RRD Settings
cat <<EOF > $opennms_etc/opennms.properties.d/rrd.properties
org.opennms.rrd.storeByGroup=true
org.opennms.rrd.storeByForeignSource=true
EOF

# Simplify Eventd
cat <<EOF > $opennms_etc/eventconf.xml
<?xml version="1.0"?>
<events xmlns="http://xmlns.opennms.org/xsd/eventconf">
  <global>
    <security>
      <doNotOverride>logmsg</doNotOverride>
      <doNotOverride>operaction</doNotOverride>
      <doNotOverride>autoaction</doNotOverride>
      <doNotOverride>tticket</doNotOverride>
      <doNotOverride>script</doNotOverride>
    </security>
  </global>
  <event-file>events/opennms.ackd.events.xml</event-file>
  <event-file>events/opennms.alarm.events.xml</event-file>
  <event-file>events/opennms.alarmChangeNotifier.events.xml</event-file>
  <event-file>events/opennms.bsm.events.xml</event-file>
  <event-file>events/opennms.capsd.events.xml</event-file>
  <event-file>events/opennms.config.events.xml</event-file>
  <event-file>events/opennms.correlation.events.xml</event-file>
  <event-file>events/opennms.default.threshold.events.xml</event-file>
  <event-file>events/opennms.discovery.events.xml</event-file>
  <event-file>events/opennms.internal.events.xml</event-file>
  <event-file>events/opennms.linkd.events.xml</event-file>
  <event-file>events/opennms.mib.events.xml</event-file>
  <event-file>events/opennms.ncs-component.events.xml</event-file>
  <event-file>events/opennms.pollerd.events.xml</event-file>
  <event-file>events/opennms.provisioning.events.xml</event-file>
  <event-file>events/opennms.minion.events.xml</event-file>
  <event-file>events/opennms.remote.poller.events.xml</event-file>
  <event-file>events/opennms.reportd.events.xml</event-file>
  <event-file>events/opennms.syslogd.events.xml</event-file>
  <event-file>events/opennms.ticketd.events.xml</event-file>
  <event-file>events/opennms.tl1d.events.xml</event-file>
  <event-file>events/opennms.catch-all.events.xml</event-file>
</events>
EOF

# WebUI Services
cat <<EOF > $opennms_etc/service-configuration.xml
<?xml version="1.0"?>
<service-configuration xmlns="http://xmlns.opennms.org/xsd/config/vmmgr">
  <service>
    <name>OpenNMS:Name=Manager</name>
    <class-name>org.opennms.netmgt.vmmgr.Manager</class-name>
    <invoke at="stop" pass="1" method="doSystemExit"/>
  </service>
  <service>
    <name>OpenNMS:Name=TestLoadLibraries</name>
    <class-name>org.opennms.netmgt.vmmgr.Manager</class-name>
    <invoke at="start" pass="0" method="doTestLoadLibraries"/>
  </service>
  <service>
    <name>OpenNMS:Name=Eventd</name>
    <class-name>org.opennms.netmgt.eventd.jmx.Eventd</class-name>
    <invoke at="start" pass="0" method="init"/>
    <invoke at="start" pass="1" method="start"/>
    <invoke at="status" pass="0" method="status"/>
    <invoke at="stop" pass="0" method="stop"/>
  </service>
  <service>
    <name>OpenNMS:Name=JettyServer</name>
    <class-name>org.opennms.netmgt.jetty.jmx.JettyServer</class-name>
    <invoke at="start" pass="0" method="init"/>
    <invoke at="start" pass="1" method="start"/>
    <invoke at="status" pass="0" method="status"/>
    <invoke at="stop" pass="0" method="stop"/>
  </service>
</service-configuration>
EOF

# WebUI Settings
cat <<EOF > $opennms_etc/opennms.properties.d/webui.properties
org.opennms.web.console.centerUrl=/status/status-box.jsp,/geomap/map-box.jsp,/heatmap/heatmap-box.jsp
org.opennms.security.disableLoginSuccessEvent=true
EOF

# TODO: the following is due to some issues with the datachoices plugin
cat <<EOF > $opennms_etc/org.opennms.features.datachoices.cfg
enabled=false
acknowledged-by=admin
acknowledged-at=Mon Jan 01 00\:00\:00 EDT 2018
EOF

# Logging
sed -r -i 's/value="DEBUG"/value="WARN"/' $opennms_etc/log4j2.xml
sed -r -i '/manager/s/WARN/DEBUG/' $opennms_etc/log4j2.xml

echo "### Forcing OpenNMS to be read-only in terms of administrative changes..."

security_cfg=$opennms_home/jetty-webapps/opennms/WEB-INF/applicationContext-spring-security.xml
cp $security_cfg $security_cfg.bak
sed -r -i 's/ROLE_ADMIN/ROLE_DISABLED/' $security_cfg
sed -r -i 's/ROLE_PROVISION/ROLE_DISABLED/' $security_cfg

echo "### Running OpenNMS install script..."

$opennms_home/bin/runjava -S /usr/java/latest/bin/java
touch $opennms_etc/configured

echo "### Configurng Grafana..."
echo "### WARNING: Grafana doesn't support multi-host database configuration..."

grafana_cfg=/etc/grafana/grafana.ini
cp $grafana_cfg $grafana_cfg.bak
sed -r -i "s/;domain = localhost/domain = $webui_endpoint/" $grafana_cfg
sed -r -i "s/;root_url = .*/root_url = %(protocol)s:\/\/%(domain)s:\/grafana/" $grafana_cfg
sed -r -i "s/;type = sqlite3/type = postgres/" $grafana_cfg
sed -r -i "s/;host = 127.0.0.1:3306/host = $postgres_server:5432/" $grafana_cfg
sed -r -i "/;name = grafana/s/;//" $grafana_cfg
sed -r -i "s/;user = root/user = grafana/" $grafana_cfg
sed -r -i "s/;password =/password = grafana/" $grafana_cfg
sed -r -i "s/;provider = file/provider = postgres/" $grafana_cfg
sed -r -i "s/;provider_config = sessions/provider_config = user=grafana password=grafana host=$postgres_server port=5432 dbname=grafana sslmode=disable/" $grafana_cfg

echo "*:*:*:postgres:postgres" > ~/.pgpass
chmod 0600 ~/.pgpass
if ! psql -U postgres -h $postgres_server -lqt | cut -d \| -f 1 | grep -qw grafana; then
  echo "Creating grafana user and database in PostgreSQL..."
  createdb -U postgres -h $postgres_server -E UTF-8 grafana
  createuser -U postgres -h $postgres_server grafana
  psql -U postgres -h $postgres_server -c "alter role grafana with password 'grafana';"
  psql -U postgres -h $postgres_server -c "grant all on database grafana to grafana;"
fi
rm -f ~/.pgpass

echo "### Enabling and starting Grafana server..."

systemctl enable grafana-server
systemctl start grafana-server
sleep 10

grafana_key=`curl -X POST -H "Content-Type: application/json" -d '{"name":"opennms-ui", "role": "Viewer"}' http://admin:admin@localhost:3000/api/auth/keys 2>/dev/null | jq .key - | sed 's/"//g'`
if [ "$grafana_key" != "null" ]; then
  cat <<EOF > $opennms_etc/opennms.properties.d/grafana.properties
org.opennms.grafanaBox.show=true
org.opennms.grafanaBox.hostname=$webui_endpoint
org.opennms.grafanaBox.port=80
org.opennms.grafanaBox.basePath=/grafana
org.opennms.grafanaBox.apiKey=$grafana_key
EOF
fi

echo "### Enabling Helm..."

helm_url="http://admin:admin@localhost:3000/api/plugins/opennms-helm-app/settings"
helm_enabled=`curl "$helm_url" 2>/dev/null | jq '.enabled'`
if [ "$helm_enabled" != "true" ]; then
  curl -XPOST "$helm_url" -d "" 2>/dev/null
fi

echo "### Configuring HTTP Proxy..."

cat <<EOF > /etc/httpd/conf.d/opennms.conf
<VirtualHost *:80>
  ServerName $hostname
  ErrorLog "logs/opennms-error_log"
  CustomLog "logs/opennms-access_log" common
  <Location /opennms>
    Order deny,allow
    Allow from all
    ProxyPass http://127.0.0.1:8980/opennms
    ProxyPassReverse http://127.0.0.1:8980/opennms
  </Location>
  <Location /hawtio>
    Order deny,allow
    Allow from all
    ProxyPass http://127.0.0.1:8980/hawtio
    ProxyPassReverse http://127.0.0.1:8980/hawtio
  </Location>
  <Location /grafana>
    Order deny,allow
    Allow from all
    ProxyPass http://127.0.0.1:3000
    ProxyPassReverse http://127.0.0.1:3000
  </Location>
</VirtualHost>
EOF

systemctl enable httpd
systemctl start httpd

echo "### Enabling and starting OpenNMS..."

sleep 180
systemctl daemon-reload
systemctl enable opennms
systemctl start opennms
