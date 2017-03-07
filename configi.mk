.PHONY: test clean_cwtest
cwtest.lua:
	$(CP) vendor/lua/cwtest.lua .
test: development cwtest.lua
	bin/tests.lua
clean_cwtest:
	$(RM) $(RMFLAGS) cwtest.lua
CLEAN+= clean_cwtest
