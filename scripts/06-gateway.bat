@echo off
title Gateway (port 7070)
set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot
"%JAVA_HOME%\bin\java" -DGATEWAY_PORT=7070 -DBIZTREE_HOST=localhost -DBIZTREE_PORT=3002 -DENYMAN_HOST=localhost -DENYMAN_PORT=3003 -DPACMAN_HOST=localhost -DPACMAN_PORT=3004 -DKEYSMITH_HOST=localhost -DKEYSMITH_PORT=3005 -DKEYCLOAK_HOST=localhost -DKEYCLOAK_PORT=8080 -DCORS_ALLOWED_ORIGINS=http://localhost:4200 -DLOG_LEVEL_ROOT=ERROR -DLOG_LEVEL_MIR0N=DEBUG -jar C:\aegis-miron\esquire.services\gateway\target\esquire-gateway.jar
pause
