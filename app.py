#!/usr/bin/env python3

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

SorterBotDevStack(app, "sorterbot-dev", env=core.Environment(account=os.getenv("AWS_ACCOUNT_ID"), region=os.getenv("AWS_REGION")))
SorterBotProdStack(app, "sorterbot-prod", env=core.Environment(account=os.getenv("AWS_ACCOUNT_ID"), region=os.getenv("AWS_REGION")))

app.synth()
