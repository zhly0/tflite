from __future__ import absolute_import
from __future__ import division
from __future__ import print_function

import os
import re
import math
import subprocess
import numpy as np
import tensorflow as tf
import matplotlib.pyplot as plt
from scipy.stats import gaussian_kde

'''
This program is used to visualize the result of different
models (float/fake-quant/quantized) given the same input data
'''

tf.app.flags.DEFINE_string(
    'frozen_pb', None, 'The GraphDef file of the freeze_graph. (float input)')
tf.app.flags.DEFINE_string(
    'float_tflite_model', None, 'The TFLite file of the tensorflow lite model. (float input)')
tf.app.flags.DEFINE_string(
    'quantized_tflite_model', None, 'The TFLite file of the tensorflow lite model. (uint8 input)')
tf.app.flags.DEFINE_string(
    'input_node_name', 'input', 'The name of the input node.')
tf.app.flags.DEFINE_string(
    'input_float_npy', None, 'The numpy file of the float input data.')
tf.app.flags.DEFINE_string(
    'input_quantized_npy', None, 'The numpy file of the uint8 input data.')
tf.app.flags.DEFINE_string(
    'output_node_name', None, 'The name of the output node for visualization.')
tf.app.flags.DEFINE_string(
    'tensorflow_dir', None, 'The directory where the tensorflow are stored')
tf.app.flags.DEFINE_boolean(
    'dump_data', False, 'Whether to dump the input and output data for each batch or not.')
tf.app.flags.DEFINE_string(
    'evaluation_mode', 'statistics', 'The evaluation method.')
#tf.app.flags.DEFINE_string(
#    'evaluation_config', None, 'Additional configurations for specific evaluation mode.')

FLAGS = tf.app.flags.FLAGS

def draw_distribution(ax, title, data):
  data = data.flatten()
  ax.hist(data, bins=100, edgecolor='gray', facecolor='green', alpha=0.5, density=True)
  density = gaussian_kde(data)
  density.covariance_factor = lambda : .05
  density._compute_covariance()
  xs = np.linspace(np.min(data), np.max(data), 200)
  ax.plot(xs, density(xs), color='black', linewidth=2)
  ax.set_ylabel('density')
  ax.title.set_text(title)

def get_tflite_quantization_info(model):
  cmd = [FLAGS.tensorflow_dir + '/bazel-bin/tensorflow/contrib/lite/utils/dump_tflite',
          '{}'.format(model)]
  out = subprocess.check_output(cmd)
  for line in out.splitlines():
    if 'name ' + FLAGS.output_node_name in line:
      result = re.search('quantization \((?P<scale>[0-9\.]+) (?P<zero>[0-9\.]+)\)', line)
      return float(result.group('scale')), int(result.group('zero'))
  raise ValueError('Quantization of the output node is not embedded inside the TFLite model')

def get_tflite_tensor_index(model, tensor_name):
  cmd = [FLAGS.tensorflow_dir + '/bazel-bin/tensorflow/contrib/lite/utils/dump_tflite',
          '{}'.format(model)]
  out = subprocess.check_output(cmd)
  for line in out.splitlines():
    if 'name ' + FLAGS.output_node_name in line:
      result = re.search('(?P<index>[0-9]+): name ' + tensor_name, line)
      return int(result.group('index'))
  raise ValueError('Tensor name \'{}\' is not defined in the TFLite model'.format(tensor_name))

def process_tflite_model_with_data_and_type(model_fn, input_data_fn, output_idx, inference_type_str):
  tmp_output_fn = 'output_tmp.npy'
  cmd = [FLAGS.tensorflow_dir + '/bazel-bin/tensorflow/contrib/lite/utils/run_tflite',
      '--tflite_file={}'.format(model_fn),
      '--batch_xs={}'.format(input_data_fn),
      '--batch_ys={}'.format(tmp_output_fn),
      '--output_tensor_idx={}'.format(output_idx),
      '--inference_type=' + inference_type_str]
  subprocess.check_output(cmd)
  output_data = np.load(tmp_output_fn)
  subprocess.check_output(['rm', tmp_output_fn])
  return output_data

def process_frozen_pb_with_data(model_fn, input_float):
  graph_def = tf.GraphDef()
  with tf.gfile.GFile(model_fn, "rb") as f:
    graph_def.ParseFromString(f.read())

  with tf.Session() as sess:
    tf.import_graph_def(graph_def, name='')
    graph = sess.graph
    x = graph.get_tensor_by_name('{}:0'.format(FLAGS.input_node_name))
    y = graph.get_tensor_by_name('{}:0'.format(FLAGS.output_node_name))
    output_float = sess.run(y, feed_dict={x: input_float})
  return output_float

def main(_):

  pb_model_fns = FLAGS.frozen_pb.split() if FLAGS.frozen_pb else []
  float_tflite_model_fns = FLAGS.float_tflite_model.split() if FLAGS.float_tflite_model else []
  quantized_tflite_model_fns = FLAGS.quantized_tflite_model.split() if FLAGS.quantized_tflite_model else []

  if not (pb_model_fns + float_tflite_model_fns + quantized_tflite_model_fns):
    raise ValueError('At least one model is required')
  if any(float_tflite_model_fns + quantized_tflite_model_fns) and not FLAGS.tensorflow_dir:
    raise ValueError('--tensorflow_dir is required for executing tflite model')
  if any(pb_model_fns + float_tflite_model_fns) and not FLAGS.input_float_npy:
    raise ValueError('--input_float_npy is required')
  if any(quantized_tflite_model_fns) and not FLAGS.input_quantized_npy:
    raise ValueError('--input_quantized_npy is required')
  if not FLAGS.output_node_name:
    raise ValueError('--output_node_name is required')

  tf.logging.set_verbosity(tf.logging.INFO)

  input_float = np.load(FLAGS.input_float_npy) if FLAGS.input_float_npy else None

  output_buffers = []
  tf.logging.info('Process frozen_pb')
  if any(pb_model_fns):
    def process_frozen_pb(model):
      return (model, process_frozen_pb_with_data(model, input_float))
    output_buffers += map(process_frozen_pb, pb_model_fns)

  tf.logging.info('Process float_tflite_model')
  if any(float_tflite_model_fns):
    def process_float_tflite_model(model):
      output_idx = get_tflite_tensor_index(model, FLAGS.output_node_name)
      return (model, process_tflite_model_with_data_and_type(model, FLAGS.input_float_npy, output_idx, 'float'))
    output_buffers += map(process_float_tflite_model, float_tflite_model_fns)

  tf.logging.info('Process quantized_tflite_model')
  if any(quantized_tflite_model_fns):
    def process_quantized_tflite_model(model):
      scale, zero_point = get_tflite_quantization_info(model)
      output_idx = get_tflite_tensor_index(model, FLAGS.output_node_name)
      def dequantize_output(output_np_array):
        return (output_np_array.astype(float) - zero_point) * scale
      return (model, dequantize_output(process_tflite_model_with_data_and_type(model, FLAGS.input_quantized_npy, output_idx, 'uint8')))
    output_buffers += map(process_quantized_tflite_model, quantized_tflite_model_fns)

  # evaluation
  tf.logging.info('Evaluate the data')

  if FLAGS.evaluation_mode == 'statistics':
    def get_statistics(numpy_data):
      data = []
      data.append('Q0: {:.6f}'.format(np.percentile(numpy_data, 0)))
      data.append('Q1: {:.6f}'.format(np.percentile(numpy_data, 25)))
      data.append('Q2: {:.6f}'.format(np.percentile(numpy_data, 50)))
      data.append('Q3: {:.6f}'.format(np.percentile(numpy_data, 75)))
      data.append('Q4: {:.6f}'.format(np.percentile(numpy_data, 100)))
      return data
    for fn, output in output_buffers:
      print('Output of model \'{}\''.format(fn))
      print('------> {}\n'.format(get_statistics(output)))

  elif FLAGS.evaluation_mode == 'plot_distribution':
    _, ax = plt.subplots(len(output_buffers), sharex='col')
    for cur_ax, cur_out in zip(ax, output_buffers):
      draw_distribution(cur_ax, cur_out[0], cur_out[1])
    plt.show()

  plt.show()

if __name__ == '__main__':
  tf.app.run()
