## Python import tool to build and populate bounce database for 
##  KumoMTA Smart SInk and Reflector Project

import csv, sqlite3

# Define sq3 database location
buildtable = 0
inputfile = "bouncedata.csv"
bouncedb = "fakebouncedata.db"
conn = sqlite3.connect(bouncedb)
curs = conn.cursor()

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

curs.executemany("INSERT INTO bounce_data (domain, code, context) VALUES (?, ?, ?);", dbvars)
conn.commit()
conn.close()


