class mysql ($admin_user = 'root',
	$admin_password) {
	package {
		mysql-server :
			ensure => present
	}
	package {
		mysql-client :
			ensure => present
	}

	# Workaround for Puppet 2.7.10 & Ubuntu 11.10
	service {
		mysql :
			enable => true,
			ensure => running,
			hasstatus => true,
			hasrestart => true,
			status => '/usr/sbin/service mysql status | grep start',
			require => Package['mysql-server'],
	}
	
	define db ($dbname, $ensure = 'present') {
		case $ensure {
			'present': {
				exec {
					"mysql-create-db-${dbname}" :
						unless =>
						"/usr/bin/mysql --user='${mysql::admin_user}' --password='${mysql::admin_password}' '${dbname}'",
						command =>
						"/usr/bin/mysqladmin -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' create '${dbname}'",
						logoutput => true,
						require => Service['mysql'],
				}
			}
			'absent': {
				exec {
					"mysql-drop-db-${dbname}" :
						onlyif =>
						"/usr/bin/mysql --user='${mysql::admin_user}' --password='${mysql::admin_password}' '${dbname}'",
						command =>
						"/usr/bin/mysqladmin -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' --force drop '${dbname}'",
						logoutput => true,
						require => Service['mysql'],
				}
			}
		}

		#      exec { "grant-${dbname}-db":
		#        unless => "/usr/bin/mysql -u${user} -p${password} ${dbname}",
		#        command => "/usr/bin/mysql -uroot -e \"grant all on ${dbname}.* to ${user}@localhost identified by '$password';\"",
		#        require => [Service["mysqld"], Exec["create-${dbname}-db"]]
		#      }

	}
	
	define user ($user, $password, $ensure = 'present') {
		case $ensure {
			'present': {
				exec {
					"mysql-create-user-${user}" :
						unless =>
						"/usr/bin/mysql --user='${user}' --password='${password}'",
						command =>
						"/usr/bin/mysql -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' -e \"CREATE USER '${user}'@localhost IDENTIFIED BY '${password}'\"",
						logoutput => true,
						require => Service['mysql'],
				}
			}
			'absent': {
				exec {
					"mysql-drop-user-${user}" :
						onlyif =>
						"/usr/bin/mysql --user='${user}' --password='${password}'",
						command =>
						"/usr/bin/mysql -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' -e \"DROP USER '${user}'@localhost\"",
						logoutput => true,
						require => Service['mysql'],
				}
			}
		}
	}

	define grant ($dbname, $user, $password, $ensure = 'present') {
		case $ensure {
			'present': {
				exec {
					"mysql-grant-${dbname}-${user}" :
						unless =>
						"/usr/bin/mysql --user='${user}' --password='${password}' '${dbname}'",
						command =>
						"/usr/bin/mysql -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' -e \"GRANT ALL ON ${dbname}.* TO '${user}'@localhost\"",
						logoutput => true,
						require => Service['mysql'],
				}
			}
			'absent': {
				exec {
					"mysql-revoke-${dbname}-${user}" :
						onlyif =>
						"/usr/bin/mysql --user='${user}' --password='${password}' '${dbname}'",
						command =>
						"/usr/bin/mysql -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' -e \"REVOKE ALL ON ${dbname}.* FROM '${user}'@localhost\"",
						logoutput => true,
						require => Service['mysql'],
				}
			}
		}
	}
	
}
