@echo off
title KeySmith (port 3005)
set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot
"%JAVA_HOME%\bin\java" -DKEYSMITH_PORT=3005 -DDB_KEYSMITH_VENDOR=dev-postgres -DDB_KEYSMITH_HOST=192.168.1.104 -DDB_KEYSMITH_PORT=5432 -DDB_KEYSMITH_NAME=esq2025 -DDB_KEYSMITH_USERNAME=esq2025 -DDB_KEYSMITH_PASSWORD=q -DLOG_LEVEL_ROOT=ERROR -DLOG_LEVEL_MIR0N=DEBUG -jar C:\aegis-miron\esquire.services\keySmith\target\esquire-key-smith.jar
pause
