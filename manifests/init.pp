/**
 * Class Parameters:
 * admin_user:        MySQL superuser, default is 'root'
 * admin_password:    MySQL superuser password
 */
class mysql (
  $admin_user = 'root',
  $admin_password,
  $bind_address = '127.0.0.1',      # Always set to 127.0.0.1 unless you have firewall
  # Default tune values inspired by: http://www.linode.com/stackscripts/view/?StackScriptID=1
  $key_buffer = '300M',             # 75%
  $sort_buffer_size = '4M',         # 1%
  $read_buffer_size = '4M',         # 1%
  $read_rnd_buffer_size = '4M',     # 1%
  $myisam_sort_buffer_size = '20M', # 5%
  $query_cache_size = '60M'         # 15%
) {
  package {
    mysql-server: ensure => present;
    mysql-client: ensure => present;
  }
  augeas { mysql:
  	context => '/files/etc/mysql/my.cnf',
  	changes => [
  	  "set */bind-address                    ${bind_address}",
  	  "set */key_buffer                      ${key_buffer}",
  	  "set target[3]/sort_buffer_size        ${sort_buffer_size}",
  	  "set target[3]/read_buffer_size        ${read_buffer_size}",
  	  "set target[3]/read_rnd_buffer_size    ${read_rnd_buffer_size}",
  	  "set target[3]/myisam_sort_buffer_size ${myisam_sort_buffer_size}",
  	  "set */query_cache_size                ${query_cache_size}",
  	],
  	require => Package['mysql-server'],
  }

  # Workaround for Puppet 2.7.10 & Ubuntu 11.10
  service { mysql:
    enable     => true,
    ensure     => running,
    hasstatus  => true,
    hasrestart => true,
    status     => '/usr/sbin/service mysql status | grep start',
    require    => Package['mysql-server'],
    subscribe  => Augeas['mysql bind-address'],
  }

  # Set root password
  exec { mysql-root-password:
  	command => "/usr/bin/mysqladmin --verbose --user='${admin_user}' password '${admin_password}'",
  	onlyif => "/usr/bin/mysql --user='${admin_user}' mysql",
  	logoutput => true,
  	require => Service['mysql']
  }


  define db ($ensure = 'present') {
  	$dbname = $name
    case $ensure {
      'present': {
        exec { "mysql-create-db-${dbname}" :
          unless    => "/usr/bin/mysql --user='${mysql::admin_user}' --password='${mysql::admin_password}' '${dbname}'",
          command   => "/usr/bin/mysqladmin -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' create '${dbname}'",
          logoutput => true,
          require   => Exec['mysql-root-password']
        }
      }
      'absent': {
        exec { "mysql-drop-db-${dbname}" :
          onlyif    => "/usr/bin/mysql --user='${mysql::admin_user}' --password='${mysql::admin_password}' '${dbname}'",
          command   => "/usr/bin/mysqladmin -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' --force drop '${dbname}'",
          logoutput => true,
          require   => Exec['mysql-root-password']
        }
      }
    }

  }

  define user ($password, $ensure = 'present') {
  	$user = $name
    case $ensure {
      'present': {
        exec { "mysql-create-user-${user}" :
          unless    => "/usr/bin/mysql --user='${user}' --password='${password}'",
          command   => "/usr/bin/mysql -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' -e \"CREATE USER '${user}'@localhost IDENTIFIED BY '${password}'\"",
          logoutput => true,
          require   => Exec['mysql-root-password']
        }
      }
      'absent': {
        exec { "mysql-drop-user-${user}" :
          onlyif    => "/usr/bin/mysql --user='${user}' --password='${password}'",
          command   => "/usr/bin/mysql -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' -e \"DROP USER '${user}'@localhost\"",
          logoutput => true,
          require   => Exec['mysql-root-password']
        }
      }
    }
  }

  define grant ($dbname, $user, $ensure = 'present') {
    case $ensure {
      'present': {
        exec { "mysql-grant-${dbname}-${user}" :
          unless    => "/usr/bin/mysql --user='${mysql::admin_user}' --password='${mysql::admin_password}' --batch -e \"SELECT user FROM db WHERE Host='localhost', Db='${dbname}', User='${user}'\" mysql | /bin/grep '${user}'",
          command   => "/usr/bin/mysql --verbose --user='${mysql::admin_user}' --password='${mysql::admin_password}' -e \"GRANT ALL ON ${dbname}.* TO '${user}'@localhost\" \
                      ; /usr/bin/mysqladmin --verbose --user='${mysql::admin_user}' --password='${mysql::admin_password}' flush-privileges",
          logoutput => true,
          require   => [ Mysql::Db[$dbname], Mysql::User[$user] ]
        }
      }
      'absent': {
        exec { "mysql-revoke-${dbname}-${user}" :
          onlyif    => "/usr/bin/mysql --user='${mysql::admin_user}' --password='${mysql::admin_password}' --batch -e \"SELECT user FROM db WHERE Host='localhost', Db='${dbname}', User='${user}'\" mysql | /bin/grep '${user}'",
          command   => "/usr/bin/mysql -v --user='${mysql::admin_user}' --password='${mysql::admin_password}' -e \"REVOKE ALL ON ${dbname}.* FROM '${user}'@localhost\" \
                      ; /usr/bin/mysqladmin --verbose --user='${mysql::admin_user}' --password='${mysql::admin_password}' flush-privileges",
          logoutput => true,
          require   => Exec['mysql-root-password']
        }
      }
    }
  }

}
