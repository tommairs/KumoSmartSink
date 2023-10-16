# Smart Sink and Reflector policy using KumoMTA
## A smart sink and reflector tool for email testing

## Preface
This is offered as a free simulator if you want to build it yourself or experiment on your own, just follow the instructions below.
It can also be available with a very large database of response codes for a fee as a SaaS model.  If that is interesting to you send your inquiry to [sales@aasland.com](mailto:sales@aasland.com).

## Description
This config policy defines [KumoMTA](https://kumomta.com) as a smart sink and
reflector to simulate real world delivery testing.
It will consume and process all incoming messages in the
following ways:
* incomming mail will be evaluated against the behaviour
    file at behave.toml
* mail will be bounced (5xx), Deferred (4xx), or accepted (250)
    based on the percentages in that file per domain
* TBD: will add oob and fbl responses in the future
* TBD: might add opens and clicks in the future

Sample behave.toml file:

[yahoo.com]

  bounce 20

  defer  20

  - all remailing will be accepted and dropped

## Install and Usage
Install KumoMTA as per the instructions here: `https://docs.kumomta.com/userguide/installation/overview/`


- Important. --------------------------

Repeat this step for all domains you want to simulate

Modify your DNS to add fake redirection to this new mail server.  For instance, if your sink server domain is `sink.mydomain.com` and the IP is 100.100.100.100, then you should add something like:

not-yahoo.sink.mydomain.com A  100.100.100.100
i
not-yahoo.sink.mydomain.com MX 10 not-yahoo.sink.mydomain.com

Now when you send an email to bob@not-yahoo.sink.mydomain.com, it will land at your sink server.
\- -------------------------------------

Clone this repo to a separate working folder.

Modify the sample bounce files or add your own with a similar format.
The Python importer will look for bouncedata.csv first and import it if possible.
If that file does not exist, it will prompt for the location of a suitable 
import file.  The file must be CSV with only the named columns `domain`,`code`,`context`.

Execute the Python importer script `sq3dbimporter.py`.  If you used files that are not named `bouncedata.cvs` you will need to provide those file names during the process.

Modify the `listener_domains` file to include your sending domain in the `relay_from` format (sample is provided)

Copy the contents of this directory to /opt/kumomta/etc/policy/

Restart KumoMTA with a stop/start
``` bash
sudo systemctl stop kumomta
sudo systemctl start kumomta
```

Tail the system journal to make sure there are no errors

```bash
journalctl -f -n 50 -u kumomta
```

^^ if you leave this running you will see a running log of injection and processing activity.

You can test this from another terminal window with swaks:

`swaks --to you@not-yahoo.yourdomain.com --from generator@your.sendingdomain.com --server localhost`

If that all works, then you can set up your te4st campaign send by replacing all the real domains to fake domains.  
IE: sally@yahoo.com becomes sally@not-yahoo.sink.mydomain.com based on the sample scenario above.




