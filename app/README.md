Brainstorming!


* Deployment
  * Should run as a container that others can download/run (in case there are
    problems)
  * Should have several vulnerable services
  * Preferably different software stacks
    * Can I re-use BSidesSF 101 challenges? Two birds etc
    * PHP
    * ASPX
    * Java?
    * Nginx + Apache

Users can write exploits + Suricata rules

For each vuln...
* We need a vulnerability
* Also a description we can give to the user
* Also examples of "good" usage - maybe ranked easy/medium/hard?
  * Can users also submit good checks (things that shouldn't be caught?)
* Some basic examples of "bad" usage - maybe we can also do easy/medium/hard?
* User is given a basic request to edit
* By default, no rules are applied
* User is given some particular payload to try and run - maybe echo something?
* User is given the option to get a basic working exploit

Suricata rules
* Players should be able to write + test rules
* Players should be able to "export" their rules so other players can use them
* That means I need a database of some kind, eww :(

Vuln types:
* Path traversal
* SQL injection
* Command injection
* XXE / XML injection?
* Something something header? Like F5?
* Arbitrary file upload
* Authentication bypass - JWT with Null auth?
* Stack buffer overflow (easy!)
* Deserialization (PHP?)
* Backdoor password usage
* Template injection

Other thoughts:
* Need things that work on both get/post
* Need JSON/XML bodies

Types of levels:
1) Informational
2) Exploit this vuln
3) Exploit this vuln w/ Suricata rule in-place
4) Detect this exploit w/ Suricata rule
