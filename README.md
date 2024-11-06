# nginx
A custom NGINX image loaded with all of the goodies I need to make a success proxy server in my environments.

# Using this image

Start in the Services Directory. The services directory contains a http and scripts sub-directory that store necessary files to run and customize the container. \
The http directory contains an nginx.conf file that is used to serve a customized nginx configuration. Take note of the www directory that contains custom static html files that will be served by the nginx server. \
The scripts directory contain helper scripts that are used to automate the addition of all .conf, www, and ssl files to the container. The directory structure should look like this:

Services: This is the root directory that you should be working in. \
Services\http : This directory serves HTTP content on the ports specified in ports.txt \
Services\http\ports.txt : This file contains the ports that the HTTP server will listen on. \
Services\http\nginx.conf : This is the default file used to run the server. Feel free to customize this. \
services\http\ssl-internal.conf : This file contains an SSL usage directive and the helper scripts will find it, and inject it into the container. \
Services\http\www : This is where you would put any static HTML assets. \
Services\http\www\index.html : This is an example customized HTML page. \
Services\http\Makefile : This contains various commands to use for building and testing the container \
Services\scripts : No need to touch anything in here. These scripts help automate building and updating the customized containers \
Services\ssl : This folder holds all of the SSL certificates. The configs should reference these via `/etc/ssl/certs/some-cert.crt` \
Services\ssl\ca : This folder holds all of the client certs needed to avoid certificate issues when Reverse Proxying. \
Services\ssl\ca-bundle : This folder holds all of the CA certs needed to avoid certificate issues when Reverse Proxying. \

## Building a new service

The easiest way to get started is to copy the `http` directory and rename it to the name of your service. For example, `https`. \
Then, customize the `nginx.conf` file so that it serves or proxies the content you need. \
Navigate to the `https` directory and you can run `make debug` or `make all` to build the container. The various explanations of the Makefile are listed below.

### Service-Specific Makefile

There may be some additional commands added over time, however, these commands should not change.

| **Target**              | **Description**                                                                                                 |
|-------------------------|-----------------------------------------------------------------------------------------------------------------|
| `.PHONY`                | Declares targets that are not files, ensuring they run every time.                                             |
| `download-logs`         | Downloads logs from the container to `./logs` if the container exists.                                         |
| `load-image`            | Loads the Docker image from a specified tar file.                                                              |
| `stop`                  | Stops the container, downloading logs before stopping.                                                         |
| `start`                 | Starts the container if it’s stopped.                                                                          |
| `start-attach`          | Starts and attaches to the container, showing live log output.                                                 |
| `restart`               | Restarts the container by stopping and then starting it.                                                       |
| `remove`                | Removes the container and associated anonymous volumes.                                                        |
| `shell`                 | Opens an interactive shell inside the container for debugging or inspection.                                   |
| `remove-volumes`        | Deletes volumes associated with the container.                                                                 |
| `clean-container`       | Stops, removes the container, and cleans up its volumes.                                                       |
| `create-container`      | Creates a new container with configured volumes and port mappings.                                             |
| `copy-configs`          | Copies `.conf` files to the container’s `/etc/nginx` directory.                                                |
| `copy-ssl`              | Copies SSL certificates from the specified path to the container.                                              |
| `copy-www`              | Copies website files from the `www` directory to the container’s `/var/www/` directory.                        |
| `update`                | Updates configuration files and certificates in the container, then restarts it.                               |
| `debug`                 | Sets up the container for debugging by loading, creating, and attaching to it with live logs.                  |
| `all`                   | Executes a full setup by loading, cleaning, creating, and starting the container with all necessary files.      |
| `run`                   | Runs the `all` target, ensuring the container is fully set up and running.                                     |

## Running http

To run the stock http server, navigate to the `http` directory and run `make all`. This will build the container and start it. \

```bash
cd Services\http
make all
```

To stop the container, run `make stop`. \

```bash
cd Services\http
make stop
```

To run the container in debug mode, run `make debug`. \

```bash
cd Services\http
make debug
Press Ctrl+C to exit
Press Ctrl+Z to detach
```

# Attribution

The Dockerfile used in this build is pulled from : https://github.com/byjg/docker-nginx-extras