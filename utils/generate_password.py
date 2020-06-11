"""
A random password generator. It generates a password of given length (as first CLI argument), from ASCII letters (uppercase and lowercase), and numbers.
"""

import sys
import random
import string
from pathlib import Path

chars = string.ascii_letters + string.digits
password = ''.join(random.choice(chars) for i in range(36))

with open(Path(__file__).parents[1].joinpath("scripts", "variables", sys.argv[1]), "w") as outfile:
    outfile.write(password)
