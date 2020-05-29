import sys
import random
import string

chars = string.ascii_letters + string.digits
password = ''.join(random.choice(chars) for i in range(36))

with open(sys.argv[1], "w") as outfile:
    outfile.write(password)
