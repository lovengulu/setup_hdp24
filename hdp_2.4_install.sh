#!/usr/bin/bash 


STACK="HDP"
STACK_VERSION="2.4"
OS_TYPE="centos7"
AMBARI_VER="2.6.1.3"
BASE_URL_AMBARI="http://public-repo-1.hortonworks.com/ambari/${OS_TYPE}/2.x/updates/${AMBARI_VER}"



fqdn_hostname=`hostname`

function setup_password_less_ssh { 
	if [ ! -f /root/.ssh/id_rsa ]; then
		cat /dev/zero | ssh-keygen -q -N ""
	fi

	cd /root/.ssh
	cat id_rsa.pub >> authorized_keys
	chmod 700 ~/.ssh
	chmod 600 ~/.ssh/authorized_keys

	reply=`ssh -o StrictHostKeyChecking=no $fqdn_hostname date`
	if [ -z "$reply" ]; then
		echo 'Error in ssh-keygen process. Please confirm manually and run the script again'
		echo 'Exiting ... '
		exit
	fi
    cd -
}


function prepare_the_environment {
	
	yum install -y ntp
	systemctl is-enabled ntpd
	systemctl enable ntpd
	systemctl start ntpd	
	
	systemctl disable firewalld
	service firewalld stop
	
	# Disable SELinux (Security Enhanced Linux).
	setenforce 0

	# Turn off iptables. 
	iptables -L		; # but first check its status 
	iptables -F
	
	# Stop PackageKit 
	service packagekit status
	service packagekit stop
	
	umask 0022

	# set ulimit
	ulimit_sn=`ulimit -Sn`
	ulimit_hn=`ulimit -Hn`
	
	if [ "$ulimit_sn" -lt 10000 -a "$ulimit_hn" -lt 10000 ] 
	then
		echo "Setting: ulimit -n 10000"
		ulimit -n 10000
	fi
	
}


function ambari_install {
	echo "INFO: Installing ambari server from:  $BASE_URL_AMBARI"
	echo "This section downloads the required packages to run ambari-server."
	
	#TODO: Remove the old one ...
	#wget -nv http://public-repo-1.hortonworks.com/ambari/centos7/2.x/updates/2.6.1.0/ambari.repo -O /etc/yum.repos.d/ambari.repo
	wget -nv ${BASE_URL_AMBARI}/ambari.repo -O /etc/yum.repos.d/ambari.repo
	yum repolist
	
	yum install -y ambari-server 
	
}

function setup_mysql {
	wget http://repo.mysql.com/mysql-community-release-el7-5.noarch.rpm
	rpm -ivh mysql-community-release-el7-5.noarch.rpm
	yum update -y 

	yum install mysql-server -y 
	# Be aware that the server binds to localhost. good enough for this install. 
	systemctl start mysqld
	
	# MySql connector download page: https://dev.mysql.com/downloads/connector/j/
	wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.45.tar.gz -O /tmp/mysql-connector-java-5.1.45.tar.gz

	cd /usr/lib
	tar xvfz /tmp/mysql-connector-java-5.1.45.tar.gz
	mkdir -p /usr/share/java/
	ln -s /usr/lib/mysql-connector-java-5.1.45/mysql-connector-java-5.1.45-bin.jar /usr/share/java/mysql-connector-java.jar
	cd - 
	
}


function ambari_server_config_and_start {
	echo "INFO: ambari_config_start:"
	echo "    Detailed explanation and instructions for manual install and configuration of ambari-server at:" 
	echo "    https://docs.hortonworks.com/HDPDocuments/Ambari-2.6.1.0/bk_ambari-installation/content/set_up_the_ambari_server.html "
	
	# setup with the MySql connector installed previously
	ambari-server setup -s 
	ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar
	ambari-server start
} 

function ambari_agent_config_and_start {
	yum install ambari-agent -y 
	# in a single-node cluster, setting the hostname is not mandatory
	# sed /etc/ambari-agent/conf/ambari-agent.ini -i.ORIG -e "s/hostname=localhost/hostname=${fqdn_hostname}/"
	ambari-agent start   
}

function download_helper_files {
	wget http://public-repo-1.hortonworks.com/HDP/tools/2.4.3.0/hdp_manual_install_rpm_helper_files-2.4.3.0.227.tar.gz
	tar zxvf hdp_manual_install_rpm_helper_files-2.4.3.0.227.tar.gz
	PATH_HDP_MANUAL_INSTALL_RPM_HELPER_FILES=`pwd`/hdp_manual_install_rpm_helper_files-2.4.3.0.227
}



function set_hadoop_config {
	# TODO: use here parameters
	# upon completion, this functions set: SERVICES_CONFIG with valid JSON configuration. 
	used_ram_gb=$1 # 10
	container_ram=$2  # 2024

	
	
	used_ram_mb="$((used_ram_gb * 1024))"
	used_ram_mb_div_10="$((used_ram_mb / 10))"
	
	# TODO: 
	# Not using the version as in the default: 
	#	"yarn.app.mapreduce.am.command-opts" : "-Xmx ...  -Dhdp.version=${hdp.version}",
	# Omitted:
	#   "mapreduce.task.io.sort.mb" 
	
# yarn.scheduler.minimum-allocation-mb=6144	  	: "$container_ram"			
# yarn.scheduler.maximum-allocation-mb=49152		: "$used_ram_mb"
# yarn.nodemanager.resource.memory-mb=49152		: "$used_ram_mb"
# mapreduce.map.memory.mb=6144					: "$container_ram"
# mapreduce.map.java.opts=-Xmx4915m				: "$used_ram_mb_div_10"
# mapreduce.reduce.memory.mb=6144				: "$container_ram"
# mapreduce.reduce.java.opts=-Xmx4915m			: "$used_ram_mb_div_10"
# yarn.app.mapreduce.am.resource.mb=6144			: "$container_ram"
# yarn.app.mapreduce.am.command-opts=-Xmx4915m	: "$used_ram_mb_div_10"
# mapreduce.task.io.sort.mb=2457
 


read -r -d '' YARN_SITE <<EOF
    {
      "yarn-site" : {
        "properties_attributes" : { },
        "properties" : {
		  "yarn.scheduler.minimum-allocation-mb" : "$container_ram",
		  "yarn.scheduler.maximum-allocation-mb" : "$used_ram_mb",
          "yarn.nodemanager.resource.memory-mb" : "$used_ram_mb"
        }
      }
    }
EOF

# There's another config, so add separator 


read -r -d '' MAPRED_SITE <<EOF
    {
      "mapred-site" : {
        "properties_attributes" : { },
        "properties" : {
			"mapreduce.map.memory.mb" :  "$container_ram",
			"mapreduce.map.java.opts" :  "-Xmx${used_ram_mb_div_10}m",
			"mapreduce.reduce.memory.mb" :  "$container_ram",
			"mapreduce.reduce.java.opts" :  "-Xmx${used_ram_mb_div_10}m",  
			"yarn.app.mapreduce.am.resource.mb" :  "$container_ram",
			"yarn.app.mapreduce.am.command-opts" :  "-Xmx${used_ram_mb_div_10}m"
        }
      }
    }
EOF

	# concatenate to $services_config all the configs created above. Separate with commas 
	
	SERVICES_CONFIG="$YARN_SITE,$MAPRED_SITE"
	
	valid_json=$(echo "[  $SERVICES_CONFIG ] " | python -m json.tool >> /dev/null && echo "0"  || echo "1" )
	if [ "$valid_json" == "1" ]; then 
		echo "***********************************************************"
		echo "ERROR: the following services configuration not in a valid JSON format:  "
		echo 
		echo "[  $SERVICES_CONFIG ] "
		echo "***********************************************************"
	fi 	
	
	}  #########  end of function     set_hadoop_config  ################



function write_single_custer_blueprint_json {
# This function expect 3 parameters: blueprint_name, cluster_name fqdn_hostname. Defaults are set below if not passed. 
# $STACK_VERSION is mandatory (TODO: Feature implemented partially. Complete implementation)
# $SERVICES_CONFIG is optionally set previously. 

stack_version_int=$(echo $STACK_VERSION | tr -d ".")

blueprint_name=${1:-single-node-hdp-cluster}
cluster_name=${2:-host_group_1}
fqdn_hostname=${3:-$fqdn_hostname}



read -r -d '' HDP_26_STACK <<EOF
        { "name" : "NODEMANAGER" },
        { "name" : "HIVE_SERVER" },
        { "name" : "SPARK2_CLIENT" },
        { "name" : "METRICS_MONITOR" },
        { "name" : "HIVE_METASTORE" },
        { "name" : "TEZ_CLIENT" },
        { "name" : "ZOOKEEPER_CLIENT" },
        { "name" : "HCAT" },
        { "name" : "SPARK2_JOBHISTORYSERVER" },
        { "name" : "WEBHCAT_SERVER" },
        { "name" : "ACTIVITY_ANALYZER" },
        { "name" : "SECONDARY_NAMENODE" },
        { "name" : "HST_AGENT" },
        { "name" : "SLIDER" },
        { "name" : "ZOOKEEPER_SERVER" },
        { "name" : "METRICS_COLLECTOR" },
        { "name" : "METRICS_GRAFANA" },
        { "name" : "YARN_CLIENT" },
        { "name" : "HDFS_CLIENT" },
        { "name" : "HST_SERVER" },
        { "name" : "MYSQL_SERVER" },
        { "name" : "HISTORYSERVER" },
        { "name" : "NAMENODE" },
        { "name" : "PIG" },
        { "name" : "ACTIVITY_EXPLORER" },
        { "name" : "MAPREDUCE2_CLIENT" },
        { "name" : "AMBARI_SERVER" },
        { "name" : "DATANODE" },
        { "name" : "APP_TIMELINE_SERVER" },
        { "name" : "HIVE_CLIENT" },
        { "name" : "RESOURCEMANAGER"  }
EOF
		

read -r -d '' HDP_24_STACK <<EOF
        { "name" : "NODEMANAGER"},
        { "name" : "HIVE_SERVER"},
        { "name" : "METRICS_MONITOR"},
        { "name" : "HIVE_METASTORE"},
        { "name" : "TEZ_CLIENT"},
        { "name" : "ZOOKEEPER_CLIENT"},
        { "name" : "HCAT"},
        { "name" : "WEBHCAT_SERVER"},
        { "name" : "SECONDARY_NAMENODE"},
        { "name" : "ZOOKEEPER_SERVER"},
        { "name" : "METRICS_COLLECTOR"},
        { "name" : "SPARK_CLIENT"},
        { "name" : "YARN_CLIENT"},
        { "name" : "HDFS_CLIENT"},
        { "name" : "MYSQL_SERVER"},
        { "name" : "HISTORYSERVER"},
        { "name" : "NAMENODE"},
        { "name" : "PIG"},
        { "name" : "MAPREDUCE2_CLIENT"},
        { "name" : "AMBARI_SERVER"},
        { "name" : "DATANODE"},
        { "name" : "SPARK_JOBHISTORYSERVER"},
        { "name" : "APP_TIMELINE_SERVER"},
        { "name" : "HIVE_CLIENT"},
        { "name" : "RESOURCEMANAGER"}
EOF
		

HDP_STACK=${HDP_24_STACK}

# Create JSONs
cat <<EOF > hostmapping.json
{
  "blueprint" : "${blueprint_name}",
  "default_password" : "admin",
  "host_groups" :[
    {
      "name" : "${cluster_name}",
      "hosts" : [
        {
          "fqdn" : "${fqdn_hostname}"
        }
      ]
    }
  ]
}
EOF


cat <<EOF > cluster_configuration.json
{   "configurations" : [ 
	$SERVICES_CONFIG
	], 
	"host_groups" : [ { "name" : "${cluster_name}", "components" : [ 
	    ${HDP_STACK}
      ],		
      "cardinality" : "1"
    }
  ],
  "Blueprints" : {
    "blueprint_name" : "${blueprint_name}",
    "stack_name" : "${STACK}",
    "stack_version" : "${STACK_VERSION}"
  }
}
EOF

}   ###### end of: write_single_custer_blueprint_json   ##################################################



function write_repo_json_HDP_24 {
# This function should use to select explicit version of stack. 
# Seems that the Ambari version used doesn't support it properly. 

	
cat <<EOF > repo.json
{  
   "Repositories":{
   "repo_name": "HDP-2.4.3.0",   
      "base_url":"http://public-repo-1.hortonworks.com/HDP/centos7/2.x/updates/2.4.3.0",
      "verify_base_url":true
   }
}
EOF

cat <<EOF > utils.json
{
  "Repositories": {
  "repo_name": "HDP-UTILS",
    "base_url": "http://public-repo-1.hortonworks.com/HDP-UTILS-1.1.0.20/repos/centos7",
    "verify_base_url": true
  }
}
EOF


STACK="HDP"
STACK_VERSION="2.4"
OS_TYPE="redhat7"
REPO_ID="HDP-2.4"
BASE_URL_HDP=http://public-repo-1.hortonworks.com/HDP/centos7/2.x/updates/2.4.3.0"
			 
BASE_URL_UTILS=http://public-repo-1.hortonworks.com/HDP-UTILS-1.1.0.20/repos/centos7"



wget -nv http://public-repo-1.hortonworks.com/HDP/centos7/2.x/updates/2.4.3.0/hdp.repo -O /etc/yum.repos.d/hdp.repo

#PUT /api/v1/stacks/:stack/versions/:stackVersion/operating_systems/:osType/repositories/:repoId

curl -H "X-Requested-By: ambari" -X PUT -u admin:admin http://localhost:8080/api/v1/stacks/HDP/versions/2.4.3.0/operating_systems/redhat7/repositories/HDP-2.4 -d @repo.json
curl -H "X-Requested-By: ambari" -X PUT -u admin:admin http://localhost:8080/api/v1/stacks/HDP/versions/2.4.3.0/operating_systems/redhat7/repositories/HDP-UTILS-1.1.0.20 -d @utils.json

}
	

function blueprint_install {

# Requires 3 parameters:
# 	$blueprint_name $cluster_name $dest_hostname 
# Consider adding 2 (or more) optional parameters for the memory and other config parameters. 


blueprint_name=${1:-single-node-hdp-cluster}
cluster_name=${2:-host_group_1}
dest_hostname=${3:-$fqdn_hostname}

# TODO: Once tuned for performance, can you set_hadoop_config() to set those parameters at install time.   

#set_hadoop_config
write_single_custer_blueprint_json $blueprint_name $cluster_name $dest_hostname 

#write_repo_json should register the specific stack version to install. The Ambari version used here seems not to interpret it correctly. 
#write_repo_json()


curl -H "X-Requested-By: ambari" -X POST -u admin:admin http://${dest_hostname}:8080/api/v1/blueprints/${blueprint_name} -d @cluster_configuration.json
curl -H "X-Requested-By: ambari" -X POST -u admin:admin http://${dest_hostname}:8080/api/v1/clusters/${cluster_name} -d @hostmapping.json

}

#####################  EXCECUTE  Predefined Functions #########


setup_password_less_ssh 
prepare_the_environment 
ambari_install 
setup_mysql
ambari_server_config_and_start 
ambari_agent_config_and_start
blueprint_install

date

echo "Install process can be monitored at: http://${fqdn_hostname}:8080/ "
echo "User/Password:   admin/admin"

