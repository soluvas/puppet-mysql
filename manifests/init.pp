/**
 * Class Parameters:
 * admin_user:        MySQL superuser, default is 'root'
 * admin_password:    MySQL superuser password
 */
/*
 * my-large.cnf :
skip-external-locking
key_buffer_size = 256M
max_allowed_packet = 1M
table_open_cache = 256
sort_buffer_size = 1M
read_buffer_size = 1M
read_rnd_buffer_size = 4M
myisam_sort_buffer_size = 64M
thread_cache_size = 8
query_cache_size= 16M
# Try number of CPU's*2 for thread_concurrency
thread_concurrency = 8

# Uncomment the following if you are using InnoDB tables
innodb_data_home_dir = /var/lib/mysql
innodb_data_file_path = ibdata1:10M:autoextend
innodb_log_group_home_dir = /var/lib/mysql
# You can set .._buffer_pool_size up to 50 - 80 %
# of RAM but beware of setting memory usage too high
innodb_buffer_pool_size = 256M
innodb_additional_mem_pool_size = 20M
# Set .._log_file_size to 25 % of buffer pool size
innodb_log_file_size = 64M
innodb_log_buffer_size = 8M
#innodb_flush_log_at_trx_commit = 1
innodb_flush_log_at_trx_commit = 2
innodb_lock_wait_timeout = 50

[mysqldump]
quick
max_allowed_packet = 16M

[mysql]
no-auto-rehash
# Remove the next comment character if you are not familiar with SQL
#safe-updates

[myisamchk]
key_buffer_size = 128M
sort_buffer_size = 128M
read_buffer = 2M
write_buffer = 2M

[mysqlhotcopy]
interactive-timeout

 */
class mysql (
  $admin_user                      = 'root',
  $admin_password,
  $bind_address                    = '127.0.0.1',      # Always set to 127.0.0.1 unless you have firewall
  $max_connections                 = 100,              # InnoDB 4G
  # Default MyISAM tune values from my-large.cnf
  $key_buffer                      = '256M',
  $max_allowed_packet              = '1M',
  $table_open_cache                = '256',
  $sort_buffer_size                = '1M',
  $join_buffer_size                = '8M',
  $read_buffer_size                = '1M',
  $read_rnd_buffer_size            = '4M',
  $myisam_sort_buffer_size         = '64M',
  $thread_cache_size               = 8,
  $thread_concurrency              = 8,
  $query_cache_size                = '16M',
  # see http://www.infotales.com/magento-perofrmance-optimizing-your-mysql-server/ for values below
  # http://stackoverflow.com/a/1429273/122441
  # /usr/share/doc/mysql-server-5.5/examples/my-innodb-heavy-4G.cnf.gz
  $innodb_buffer_pool_size         = '256M',  # 256-512 MB for 1 GB node
  $innodb_additional_mem_pool_size = '20M',
  $innodb_log_file_size            = '64M',
  $innodb_thread_concurrency       = 8,   # 2..4 x CPU. So for 4 cores = 8
  $innodb_log_buffer_size          = '4M',
  $innodb_flush_log_at_trx_commit  = 2,
  $innodb_flush_method             = 'O_DIRECT'
) {
  package {
    mysql-server: ensure => present;
    mysql-client: ensure => present;
  }
  service { mysql:
    enable     => true,
    ensure     => running,
    hasstatus  => true,
    hasrestart => true,
    # Workaround for Puppet 2.7.10 & Ubuntu 11.10
    status     => '/usr/sbin/service mysql status | grep start',
    require    => Package['mysql-server'],
  }

  file { '/etc/mysql/my.cnf':
  	content => template('mysql/my.cnf.erb'),
    mode    => 0644,
    require => Package['mysql-server'],
    notify  => Service['mysql'],
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
