#---+ Extensions
#---++ SqlPlugin
# **PERL**
# <h3>Setup databases connections</h3>
# Table of configuration info for all the databases you might access.
# This structure is an array of database definitions. Each database
# is defined using a hash where the fields of the array are:
# <ul>
# <li> id - identifier as referenced by the <code>database</code> parameter of the <code>%SQL</code> macro.</li>
# <li> dsn - DB driver specification; please look the driver manual for further information on a valid dsn specification.</li>
# <li> username - DB username</li>
# <li> password - DB password</li>
# </ul>
$Foswiki::cfg{SqlPlugin}{Databases} =
[
   {
      id => 'foswiki',
      dsn => 'dbi:mysql:foswiki:localhost',
      username => 'foswiki_user',
      password => 'foswiki_password',
   },
];
