
**The Deathstar**

- The Deathstar can be used to automate those pesky pre-scanning reconnaisance needed before a pentration test. 
- Automate any tools used in your daily asenal: Nmap, Openssl Scans, Nikto -- the process is up to you.

*Requirements*
- [Docker ](https://github.com/docker "Docker")is installed on your system

*Usage*

- Set the list of IPs to target with the variable *ipListLocation* (default location set to "/home/ubuntu/IPlist.txt")
-- The IPs should be stored as a .txt file with each IP denoted on its own separate line
- Results will be outputed, and then copied to the specified location (default location set to "/home/ubuntu/SCAN-RESULTS/")
-- The output will be separated by Deathstar box.

*How it works*

The Deathstar takes the IPlist.txt and parses it for the number of IPs that need to be imported. It defaults to creating 1 docker container instance for every 10 IPs listed. In this way it can be more efficent when delegating tasks (if you runn this on something like AWS you cant then also increase the processing power that the whole machine will have, in turn giving Docker Deathstars more computation resources to work with -- this is highly dependant on your needs). 

The 10 IPs then get copied into the docker container (takes a saved template -- in this case mine is named "ubuntu:v10")
- Withint ubuntu:v10 is placed the scanning tools needed and custom scripts used for pre-pen recon.

**Then you sit back and enjoy the demolition!** *"I think it is time we demonstrated the full power of this station. Set your course for Alderaan."*

Happy hacking!
