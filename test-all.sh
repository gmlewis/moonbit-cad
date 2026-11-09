#!/bin/bash -ex
moon fmt . catalog
moon info --target native . catalog
moon test -j 12 --target native . catalog
