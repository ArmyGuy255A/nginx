.PHONY: load-image stop remove remove-volumes clean-container create-container copy-configs copy-ssl start restart update all

# Define Docker image and container names
DOCKER_IMAGE = armyguy255a/nginx:alpine-1.26.2
IMAGE_FILE = armyguy255a--nginx_alpine-1.26.2.tar.gz
DOCKER_CONTAINER = nginx-$(shell basename $(CURDIR))
CURRENT_PATH = $(shell pwd)
SSL_PATH = $(shell find . .. -type d -name ssl -print -quit | xargs realpath)
WWW_PATH = $(shell find . -type d -name www -print -quit | xargs realpath)
PORT_MAPPINGS = $(shell cat ports.txt | xargs -I {} echo "-p {}")

# Download log files from the container
download-logs:
	@mkdir -p ./logs
	@echo "Downloading logs from $(DOCKER_CONTAINER) to ./logs..."
	@if docker ps -a --format '{{.Names}}' | grep -q "^$(DOCKER_CONTAINER)$$"; then \
		docker cp $(DOCKER_CONTAINER):/var/log/nginx/. ./logs/ || true; \
		echo "Logs downloaded successfully to ./logs."; \
	else \
		echo "Warning: Container $(DOCKER_CONTAINER) does not exist. Skipping log download."; \
	fi

# Load Docker image
load-image:
	@echo "Loading Docker image from $(IMAGE_FILE) as $(DOCKER_IMAGE)..."
	@sudo ../scripts/load_image.sh $(IMAGE_FILE) $(DOCKER_IMAGE)
	@echo "Docker image loaded successfully."

# Stop the container
stop: download-logs
	@echo "Stopping $(DOCKER_CONTAINER)..."
	@docker stop $(DOCKER_CONTAINER) || true
	@echo "$(DOCKER_CONTAINER) stopped."

# Start the Docker container
start:
	@echo "Starting $(DOCKER_CONTAINER)..."
	@docker start $(DOCKER_CONTAINER)
	@echo "$(DOCKER_CONTAINER) started."

# Start and attach to the container
start-attach: stop
	@echo "Attaching to $(DOCKER_CONTAINER) with live log output..."
	@echo "Press Ctrl+C to stop the container."
	@echo "Press Ctrl+Z to detach from the container and keep it running."
	@docker start $(DOCKER_CONTAINER) -a
	@echo "Detached from $(DOCKER_CONTAINER)."

# Restart the container
restart: stop start
	@echo "Restarted $(DOCKER_CONTAINER)."

# Remove the container
remove:
	@echo "Removing $(DOCKER_CONTAINER)..."
	@docker rm $(DOCKER_CONTAINER) -v || true
	@echo "$(DOCKER_CONTAINER) removed."

# Attach to the container shell
shell:
	@echo "Attaching to $(DOCKER_CONTAINER) shell..."
	@docker exec -it $(DOCKER_CONTAINER) /bin/sh

# Remove the volumes
remove-volumes:
	@echo "Removing volumes for $(DOCKER_CONTAINER)..."
	@docker volume rm $(DOCKER_CONTAINER)-web $(DOCKER_CONTAINER)-config $(DOCKER_CONTAINER)-logs $(DOCKER_CONTAINER)-certs || true
	@echo "Volumes removed for $(DOCKER_CONTAINER)."

# Stop and remove existing container and volumes
clean-container: stop remove remove-volumes
	@echo "$(DOCKER_CONTAINER) and associated volumes cleaned up."

# Create Docker container with necessary volumes and ports
create-container:
	@echo "Creating Docker container $(DOCKER_CONTAINER) with configured ports and volumes..."
	@docker create $(PORT_MAPPINGS) \
	    --name $(DOCKER_CONTAINER) \
	    -v '$(DOCKER_CONTAINER)-web:/var/www/' \
	    -v '$(DOCKER_CONTAINER)-config:/etc/nginx/' \
	    -v '$(DOCKER_CONTAINER)-logs:/var/log/nginx/' \
	    -v '$(DOCKER_CONTAINER)-certs:/etc/ssl/certs' \
	    $(DOCKER_IMAGE)
	@echo "$(DOCKER_CONTAINER) created successfully."

# Copy base nginx config and additional .conf files
copy-configs:
	@echo "Copying configuration files to $(DOCKER_CONTAINER)..."
	@for file in *.conf; do \
		docker cp "$$file" $(DOCKER_CONTAINER):/etc/nginx/$$file; \
	done
	@echo "Configuration files copied."

compile-ca-bundle:
	@echo "Compiling SSL certificates called ca-bundle.crt"
	@../scripts/compile_ca_bundle.sh
	@echo "SSL certificates compiled to Services/ssl/ca-bundle/ca-bundle.crt"
	@echo "Reference this in your nginx by adding the following line to your nginx.conf:"
	@echo ""
	@echo "ssl_client_certificate /etc/ssl/certs/ca-bundle.crt;"
	@echo "http blocks:"
	@echo "proxy_ssl_trusted_certificate /etc/ssl/certs/ca-bundle.crt;"

# Copy any used SSL files to the Docker container
copy-ssl: compile_ca_bundle
	@echo "Copying SSL certificates to $(DOCKER_CONTAINER) from $(SSL_PATH)..."
	@../scripts/copy_ssl_certs.sh $(DOCKER_CONTAINER) $(CURRENT_PATH) $(SSL_PATH)
	@echo "SSL certificates copied."

# Copy custom www files to the Docker container
copy-www:
	@echo "Copying www files to $(DOCKER_CONTAINER) from $(WWW_PATH)..."
	@../scripts/copy_www_files.sh $(DOCKER_CONTAINER) $(WWW_PATH)
	@echo "www files copied successfully."

# Update the config files and certificates for the container, then restart it
update: copy-configs copy-ssl copy-www restart
	@echo "$(DOCKER_CONTAINER) updated with new configurations and SSL certificates."

# Debugging command to view the container's logs
debug: load-image clean-container create-container copy-configs copy-ssl copy-www start-attach
	@echo "Debugging $(DOCKER_CONTAINER) with live log output..."

# Full build and setup process
all: load-image clean-container create-container copy-configs copy-ssl copy-www start
	@echo "Full setup complete. $(DOCKER_CONTAINER) is running."

# Default target
run: all
	@echo "$(DOCKER_CONTAINER) fully set up and running."
