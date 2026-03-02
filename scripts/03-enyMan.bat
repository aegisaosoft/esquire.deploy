@echo off
title EnyMan (port 3003)
set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot
"%JAVA_HOME%\bin\java" -DENYMAN_PORT=3003 -DDB_ENYMAN_VENDOR=dev-postgres -DDB_ENYMAN_HOST=192.168.1.104 -DDB_ENYMAN_PORT=5432 -DDB_ENYMAN_NAME=esq2025 -DDB_ENYMAN_USERNAME=esq2025 -DDB_ENYMAN_PASSWORD=q -DLOG_LEVEL_ROOT=ERROR -DLOG_LEVEL_MIR0N=DEBUG -jar C:\aegis-miron\esquire.services\enyMan\target\esquire-eny-man.jar
pause
