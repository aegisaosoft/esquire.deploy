@echo off
title BizTree (port 3002)
set JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot
"%JAVA_HOME%\bin\java" -DBIZTREE_PORT=3002 -DDB_BIZTREE_VENDOR=dev-postgres -DDB_BIZTREE_HOST=192.168.1.104 -DDB_BIZTREE_PORT=5432 -DDB_BIZTREE_NAME=esq2025 -DDB_BIZTREE_USERNAME=esq2025 -DDB_BIZTREE_PASSWORD=q -DLOG_LEVEL_ROOT=ERROR -DLOG_LEVEL_MIR0N=DEBUG -jar C:\aegis-miron\esquire.services\bizTree\target\esquire-biz-tree.jar
pause
