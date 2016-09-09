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

# **PERL**
# <h3>Access Control</h3>
# Security Configuration.
# This structure is an array of hashes, each of which contains a list of
# queries that are allowed to be run.  Each item in the query list is evaluated as a regular expression
# to see if the query matches, and also evaluated for exact string equality to see if the query matches.
# For both of these checks, the input string is converted to ALL UPPERCASE, and all whitespace is
# transformed into a single space.
# If a database connection has no items defined here, then all queries are permitted.
# Either 'who' or 'queries' can be omitted, but not both.
# <ul>
# <li> id - same identifier as in the Databases configuration section.</li>
# <li> who - User or Group name.</li>
# <li> queries - List of queries.</li>
# </ul>
$Foswiki::cfg{SqlPlugin}{AccessControl} =
[
   {
      id => 'foswiki',
      who => 'WikiUserOrGroup',
      queries => [
                      'SELECT * FROM TABLE1',
                      'UPDATE TABLE1'
                 ]
   },
];

1;
