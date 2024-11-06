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

clean:
	make -C openfire clean-container
	make -C http clean-container
	make -C https clean-container
	make -C sitaware clean-container
	make -C smtp clean-container