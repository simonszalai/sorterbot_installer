#!/usr/bin/env python3

"""
Main CDK file, which deploys the production or development stack, depending on the MODE environment variable.

"""

import os
from aws_cdk import core
from dotenv import load_dotenv

from sorterbot_installer.sorterbot_dev_stack import SorterBotDevStack
from sorterbot_installer.sorterbot_prod_stack import SorterBotProdStack


app = core.App()

if os.getenv("MODE") == "production":
    load_dotenv(".env.prod")
elif os.getenv("MODE") == "development":
    load_dotenv(".env.dev")
else:
    raise Exception("No environment variable specifies deployment mode! Set MODE to 'development' or 'production'!")

dev_stack = SorterBotDevStack(app, "sorterbot-dev", env=core.Environment(account=os.getenv("AWS_ACCOUNT_ID"), region=os.getenv("DEPLOY_REGION")))
prod_stack = SorterBotProdStack(app, "sorterbot-prod", env=core.Environment(account=os.getenv("AWS_ACCOUNT_ID"), region=os.getenv("DEPLOY_REGION")))

core.Tag.add(dev_stack, "SorterBotResource", "development")
core.Tag.add(prod_stack, "SorterBotResource", "production")

app.synth()
