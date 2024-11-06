Here’s an enhanced and more professional version of your README file:

---

# **NGINX Custom Proxy Server**

A custom NGINX image preconfigured with all necessary modules and tools to create a robust and scalable reverse proxy server.

---

## **Overview**

This repository provides an easy-to-use framework for building and managing custom NGINX-based proxy servers. The provided tools and configuration files enable you to handle HTTP, HTTPS, SSL, and certificate management seamlessly in complex environments.

---

## **Directory Structure**

The project is organized as follows:

| **Directory/File**                  | **Description**                                                                                     |
|-------------------------------------|-----------------------------------------------------------------------------------------------------|
| `Services/`                         | Root directory containing service-specific configurations and helper scripts.                       |
| `Services/http/`                    | Default service directory for HTTP configuration.                                                   |
| `Services/http/ports.txt`           | Defines the ports that the HTTP server listens on.                                                  |
| `Services/http/nginx.conf`          | Primary NGINX configuration file for the HTTP service. Customizable for service-specific needs.     |
| `Services/http/www/`                | Directory for static HTML assets served by the NGINX server.                                        |
| `Services/http/www/index.html`      | Example static HTML file served by the HTTP server.                                                 |
| `Services/http/Makefile`            | Contains Makefile targets for building, running, and managing the HTTP service container.           |
| `Services/scripts/`                 | Directory containing helper scripts for automating tasks such as copying files and certificates.    |
| `Services/ssl/`                     | Directory containing SSL certificates.                                                             |
| `Services/ssl/ca/`                  | Holds client certificates required for reverse proxying.                                            |
| `Services/ssl/ca-bundle/`           | Stores compiled bundles of CA certificates.                                                        |

---

## **Getting Started**

### **Building a New Service**

1. **Copy and Rename the Default Service**:
   - Start by copying the `http` directory and renaming it to your desired service name (e.g., `https`).
   - Example:
     ```bash
     cp -r Services/http Services/https
     ```

2. **Customize the Configuration**:
   - Modify `nginx.conf` to suit the requirements of your new service.
   - Update `ports.txt` with the desired ports for the new service.

3. **Build and Run**:
   - Navigate to the new service directory and run:
     ```bash
     cd Services/https
     make all
     ```

---

### **Makefile Targets**

The Makefile in each service directory provides commands to streamline container management.

| **Target**              | **Description**                                                                                                 |
|-------------------------|-----------------------------------------------------------------------------------------------------------------|
| `.PHONY`                | Declares non-file targets to ensure they run every time.                                                       |
| `download-logs`         | Downloads container logs to the `./logs` directory.                                                            |
| `load-image`            | Loads the Docker image from a specified tar file.                                                              |
| `stop`                  | Stops the container and optionally downloads logs before stopping.                                             |
| `start`                 | Starts the container if it’s stopped.                                                                          |
| `start-attach`          | Starts and attaches to the container, displaying live logs.                                                    |
| `restart`               | Restarts the container by stopping and starting it.                                                            |
| `remove`                | Removes the container and its associated anonymous volumes.                                                    |
| `shell`                 | Opens an interactive shell session inside the container.                                                       |
| `remove-volumes`        | Deletes Docker volumes associated with the container.                                                          |
| `clean-container`       | Stops the container, removes it, and cleans up its volumes.                                                    |
| `create-container`      | Creates a new container with predefined volumes and port mappings.                                             |
| `copy-configs`          | Copies configuration files from the local directory to the container.                                          |
| `copy-ssl`              | Copies SSL certificates from the `ssl` directory into the container.                                           |
| `copy-www`              | Copies static files from the `www` directory to the container’s `/var/www/`.                                   |
| `update`                | Updates configuration files and certificates in the container, then restarts it.                               |
| `debug`                 | Runs the container in debug mode, attaching live logs for troubleshooting.                                     |
| `all`                   | Builds, cleans, and starts the container, loading all necessary configurations.                                |
| `up`                    | Alias for `all`                                                                                                |
| `down`                  | Alias for `stop                                                                                                |
| `run`                   | Runs the `all` target to fully set up and start the container.                                                 |

---

### **Using the HTTP Service**

1. **Build and Start**:
   ```bash
   cd Services/http
   make all
   ```

2. **Stop the Container**:
   ```bash
   make stop
   ```

3. **Debug Mode**:
   Run the container with live logs:
   ```bash
   make debug
   ```
   - Press `Ctrl+C` to stop.
   - Press `Ctrl+Z` to detach and keep it running.

---

## **Certificate Management**

### **Certificate Compilation**

Certificates are automatically compiled into a CA bundle by the `compile-ca-bundle.sh` script. This script combines all certificates in the `Services/ssl/ca` directory into a single bundle located in `Services/ssl/ca-bundle/ca-certificates.crt`.

To run:
```bash
cd Services/scripts
./compile-ca-bundle.sh
```

### **Proxy SSL Configuration**

NGINX is configured to support dynamic SSL handling. Ensure that:
- All certificates referenced in `.conf` files are located in the `Services/ssl/` directory.
- Custom SSL directives are automatically parsed and copied to the container using helper scripts.

---

## **Log Management**

Log files can be downloaded or viewed live:

1. **Download Logs**:
   ```bash
   make download-logs
   ```

2. **Live Logs**:
   Use the `make debug` command to view logs in real time.

---

## **Troubleshooting**

1. **Verify Configuration**:
   Run:
   ```bash
   nginx -t
   ```

2. **Check Logs**:
   Use the `debug` target or inspect the log files in `/var/log/nginx`.

3. **Certificate Issues**:
   - Ensure certificates are correctly referenced in `.conf` files.
   - Use `compile-ca-bundle.sh` to consolidate CA certificates.

---

## **Attribution**

The Dockerfile used in this build is based on:  
[ByJG Docker NGINX Extras](https://github.com/byjg/docker-nginx-extras)

---

This updated README provides a structured, professional, and comprehensive guide for building and managing your custom NGINX proxy server environment.