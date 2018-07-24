# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""
A sample app demonstrating Stackdriver Trace
"""
import google.auth
from google.cloud import pubsub_v1

from flask import Flask, render_template, request

from opencensus.trace import execution_context
from opencensus.trace.exporters import stackdriver_exporter
from opencensus.trace.exporters.transports import background_thread
from opencensus.trace.ext.flask.flask_middleware import FlaskMiddleware
from opencensus.trace.propagation import google_cloud_format
from opencensus.trace.samplers import always_on

app = Flask(__name__)

topic_name = 'tracing-demo'

# Configure Tracing
exporter = stackdriver_exporter.StackdriverExporter(
    transport=background_thread.BackgroundThreadTransport)
propagator = google_cloud_format.GoogleCloudFormatPropagator()
sampler = always_on.AlwaysOnSampler()
blacklist_paths = ['favicon.ico']

# Instrument Flask to do tracing automatically
middleware = FlaskMiddleware(
    app,
    exporter=exporter,
    propagator=propagator,
    sampler=sampler,
    blacklist_paths=blacklist_paths)

# Create Pub/Sub client
# Messages sent with the HTTP request will be published to Cloud Pub/Sub
publisher = pubsub_v1.PublisherClient()
_, project_id = google.auth.default()
topic_path = publisher.topic_path(project_id, topic_name)


@app.route('/')
def template_test():
    """
    Handle the root path for this app. Renders a simple web page displaying a
    message. The default message is Hello World but this can be overridden by
    the use of a parameter: ?string=Test
    """

    tracer = execution_context.get_opencensus_tracer()

    # Trace Pub/Sub call using Context Manager
    with tracer.start_span() as pubsub_span:
        pubsub_span.name = '[{}]{}'.format('publish', 'Pub/Sub')
        pubsub_span.add_attribute('Topic Path', topic_path)

        string = request.args.get('string')
        string = string if string else 'Hello World'
        print('Publishing string: %s' % string)
        publisher.publish(topic_path, data=string.encode('utf-8')).result()

        return render_template('template.html', my_string=string)
