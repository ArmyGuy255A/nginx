openfire-up:
	make -C openfire all

openfire-down:
	make -C openfire stop

openfire-restart:
	make -C openfire restart

http-up:
	make -C http all

http-down:
	make -C http stop

http-restart:
	make -C http restart

https-up:
	make -C https all

https-down:
	make -C https stop

https-restart:
	make -C https restart

sitaware-up:
	make -C sitaware all

sitaware-down:
	make -C sitaware stop

sitaware-restart:
	make -C sitaware restart

smtp-up:
	make -C smtp all

smtp-down:
	make -C smtp stop

smtp-restart:
	make -C smtp restart

up: openfire-up http-up https-up sitaware-up smtp-up

down: openfire-down http-down https-down sitaware-down smtp-down

.PHONY: service

# Create a new service by copying the http directory
service:
	@if [ -z "$(name)" ]; then \
		echo "Error: Please specify a service name with 'make service name=<service_name>'"; \
		exit 1; \
	fi; \
	if [ -d "$(name)" ]; then \
		echo "Error: The service '$(name)' already exists."; \
		exit 1; \
	fi; \
	echo "Creating service '$(name)'..."; \
	cp -r http $(name); \
	echo "Service '$(name)' created successfully. Customize 'Services/$(name)/nginx.conf' and 'ports.txt' as needed."


clean:
	make -C openfire clean-container
	make -C http clean-container
	make -C https clean-container
	make -C sitaware clean-container
	make -C smtp clean-container