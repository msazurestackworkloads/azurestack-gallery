#!/bin/bash

mkdir -p _out
_out/encoder-k8s ./kubernetes/template/DeploymentTemplates/script.sh > _out/customdata-k8s.txt
_out/encoder-registry ./registry/Scripts/script.sh > _out/customdata-registry.txt