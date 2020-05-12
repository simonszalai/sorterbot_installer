#!/usr/bin/env python3

import os
from aws_cdk import core

from sorterbot_installer.sorterbot_installer_stack import SorterbotInstallerStack


os.environ["AWS_ACCESS_KEY_ID"] = "AKIAIWYAS7FTOHZ32C2Q"
os.environ["AWS_SECRET_ACCESS_KEY"] = "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"

app = core.App()
env = core.Environment(account="537539036361", region="eu-central-1")
SorterbotInstallerStack(app, "sorterbot-installer", env=env)

app.synth()
