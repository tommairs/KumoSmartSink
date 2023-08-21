# KumoMTA Smart Sink and Reflector policy
## A smart sink and reflector tool for email testing

This config policy defines KumoMTA as a smart sink and
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
  # all remailing will be accepted and dropped



