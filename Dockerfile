FROM alpine:3.5
LABEL maintainer "mail@mueller-martin.net"

RUN apk update
# ca-certificates is required for pip using HTTPS URLs
# python is left out, because it's a dependency for python-dev
RUN apk add \
ca-certificates \
python2-dev \
musl-dev \
gcc \
py2-cffi \
py2-pip \
fontconfig \
cairo-dev

# Explicitly installing django and django-templates gets them removed and
# installed later again in other version by pip when installing graphite-web
RUN pip install cairocffi pytz scandir tzupdate

ENV PYTHONPATH /opt/graphite/lib/:/opt/graphite/webapp/
RUN pip install https://github.com/graphite-project/whisper/tarball/master
RUN pip install https://github.com/graphite-project/carbon/tarball/master
RUN pip install https://github.com/graphite-project/graphite-web/tarball/master

RUN cp /opt/graphite/webapp/graphite/local_settings.py.example \
/opt/graphite/webapp/graphite/local_settings.py

# Generate random string as secret key for Graphite
RUN sed -i "/SECRET_KEY/c\SECRET_KEY = \
'$(< /dev/urandom tr -dc '!\"#$%&()*+,-./0-9:;<=>?@A-Z[]^_`a-z{|}' | \
head -c${1:-32})'" /opt/graphite/webapp/graphite/local_settings.py

# Try to get timezone via tzupdate and set it in Graphite otherwise use UTC
RUN tz=$(tzupdate -p 2>/dev/null | sed -n 's/.* //;s/.$//;p'); \
[ -z "$tz" ] && tz="UTC"; sed -i "/TIME_ZONE/c\TIME_ZONE = '$tz'" \
/opt/graphite/webapp/graphite/local_settings.py

RUN cp /opt/graphite/conf/carbon.conf.example /opt/graphite/conf/carbon.conf
RUN cp /opt/graphite/conf/storage-schemas.conf.example \
/opt/graphite/conf/storage-schemas.conf

# Initialize database
RUN django-admin.py migrate --settings=graphite.settings --run-syncdb
# Fix following error when initially starting carbon-cache:
# > twisted.python.usage.UsageError: The specified reactor cannot be used,
# > failed with error: reactor already installed.
# Related issues and documentation:
# - https://bugs.launchpad.net/graphite/+bug/833196
# - https://twistedmatrix.com/trac/ticket/3785
# - http://twistedmatrix.com/documents/13.1.0/core/howto/plugin.html#auto3
# - http://twistedmatrix.com/trac/wiki/FrequentlyAskedQuestions
#   See: "When I try to install my reactor, I get errors about a reactor
#   already being installed. What gives?"
# IMPORTANT: Graphite lib must be in PYTHONPATH!
RUN python -c \
"from twisted.plugin import IPlugin, getPlugins;list(getPlugins(IPlugin))"

# Fix Graphite development server not serving static files
# See: http://stackoverflow.com/a/7639983/1532986
RUN sed -i "/'graphite\.settings',$/a\ \ '--insecure'," \
/opt/graphite/bin/run-graphite-devel-server.py

# Ports:
# TCP 2003 Line Receiver
# TCP 2004 Pickle
# TCP 8080 Graphite Development Server
EXPOSE 2003 2004 8080
CMD /opt/graphite/bin/carbon-cache.py start && \
/opt/graphite/bin/run-graphite-devel-server.py /opt/graphite
