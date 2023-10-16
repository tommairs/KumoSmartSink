## Python import tool to build and populate bounce database for 
##  KumoMTA Smart SInk and Reflector Project

import csv, sqlite3, os.path, sys

# Define sq3 database location
buildtable = 0
inputfile = "bouncedata.csv"
bouncedb = "fakebouncedata.db"
conn = sqlite3.connect(bouncedb)
curs = conn.cursor()
WelcomeText = """
This importer will look for bouncedata.csv first and import it if possible.
If that file does not exist, it will prompt for the location of a suitable 
import file.  Must be CSV with only the named columns `domain`,`code`,`context`.
"""


## MAIN
print(WelcomeText)
cont = input("Press any key to continue")

if os.path.isfile(inputfile) != True:
    inputfile = input("Enter a valid filename for the bounce CSV to import:_ ")

if os.path.isfile(inputfile) != True:
    print("not a valid file, try again")
    sys.exit()

try:
    curs.execute("SELECT * FROM bounce_data LIMIT 1")
     
    # storing the data in a list
    data_list = curs.fetchall() 
         
except sqlite3.OperationalError:
    print("No existing table")
    buildtable = 1
     
if buildtable == 1:
    curs.execute("CREATE TABLE bounce_data (domain, code, context);")

with open(inputfile,'r') as fh:
    # csv.DictReader uses first line in file for column headings by default
    dd = csv.DictReader(fh) 
    dbvars = [(i['domain'], i['code'], i['context']) for i in dd]

print(len(dbvars))

curs.executemany("INSERT INTO bounce_data (domain, code, context) VALUES (?, ?, ?);", dbvars)
conn.commit()
conn.close()


