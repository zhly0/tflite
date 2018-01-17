.PHONY: download_inceptionV3 eval_inceptionV3
.PHONY: freeze_inceptionV3 eval_inceptionV3_frozen
.PHONY: quantor_inceptionV3_frozen toco_quantor_inceptionV3
.PHONY: toco_inceptionV3 eval_quantor_inceptionV3_tflite
.PHONY: eval_inceptionV3_tflite
.PHONY: compare_toco_inceptionV3_float compare_toco_inceptionV3_uint8


########################################################
# should already defined these variables
########################################################
# TFLITE_ROOT_PATH := /home/tflite
# TF_BASE := $(TFLITE_ROOT_PATH)/tensorflow
# TF_SLIM_BASE := $(TFLITE_ROOT_PATH)/models/research/slim
# DATASET_BASE := $(TFLITE_ROOT_PATH)/datasets
# QUANTOR_BASE := $(TFLITE_ROOT_PATH)/sandbox/quantor
# TOOLS_BASE := $(TFLITE_ROOT_PATH)/sandbox/mnist/tools

########################################################
# for inceptionV3
########################################################
download_inceptionV3:
	@ wget http://download.tensorflow.org/models/inception_v3_2016_08_28.tar.gz -P $(QUANTOR_BASE)/inceptionV3
	@ tar xvf $(QUANTOR_BASE)/inceptionV3/inception_v3_2016_08_28.tar.gz -C $(QUANTOR_BASE)/inceptionV3

eval_inceptionV3:
	@ cd $(TF_SLIM_BASE) && python eval_image_classifier.py \
		--checkpoint_path=$(QUANTOR_BASE)/inceptionV3/inception_v3.ckpt \
		--eval_dir=$(QUANTOR_BASE)/inceptionV3 \
		--dataset_name=imagenet --dataset_split_name=validation \
		--dataset_dir=$(DATASET_BASE)/imagenet --model_name=inception_v3 --max_num_batches=50

freeze_inceptionV3:
	@ cd $(TF_SLIM_BASE) && python export_inference_graph.py \
		--alsologtostderr \
		--model_name=inception_v3 --dataset_name=imagenet \
		--output_file=$(QUANTOR_BASE)/inceptionV3/inceptionV3_inf_graph.pb
	@ python $(TOOLS_BASE)/save_summaries.py $(QUANTOR_BASE)/inceptionV3/inceptionV3_inf_graph.pb
	@ cd $(TF_BASE) && bazel-bin/tensorflow/python/tools/freeze_graph \
		--input_graph=$(QUANTOR_BASE)/inceptionV3/inceptionV3_inf_graph.pb \
		--input_checkpoint=$(QUANTOR_BASE)/inceptionV3/inception_v3.ckpt \
		--input_binary=true --output_graph=$(QUANTOR_BASE)/inceptionV3/frozen_inceptionV3.pb \
		--output_node_names=InceptionV3/Predictions/Reshape
	@ cd $(TF_BASE) && bazel-bin/tensorflow/tools/graph_transforms/summarize_graph \
		--in_graph=$(QUANTOR_BASE)/inceptionV3/frozen_inceptionV3.pb
	@ python $(TOOLS_BASE)/save_summaries.py $(QUANTOR_BASE)/inceptionV3/frozen_inceptionV3.pb

eval_inceptionV3_frozen:
	@ python $(QUANTOR_BASE)/eval_frozen.py \
		--dataset_name=imagenet \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--output_node_name=InceptionV3/Predictions/Reshape \
		--input_size=299 \
		--frozen_pb=$(QUANTOR_BASE)/inceptionV3/frozen_inceptionV3.pb --max_num_batches=50
		# --summary_dir=$(QUANTOR_BASE)/inceptionV3/summary/$@

quantor_inceptionV3_frozen:
	@ python $(QUANTOR_BASE)/quantor_frozen.py \
		--dataset_name=imagenet \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--frozen_pb=$(QUANTOR_BASE)/inceptionV3/frozen_inceptionV3.pb \
		--output_node_name=InceptionV3/Predictions/Reshape \
		--input_size=299 \
		--output_dir=$(QUANTOR_BASE)/inceptionV3/quantor --max_num_batches=50
		# --summary_dir=$(QUANTOR_BASE)/inceptionV3/summary/$@
	@ python $(TF_BASE)/bazel-bin/tensorflow/python/tools/freeze_graph \
		--input_graph=$(QUANTOR_BASE)/inceptionV3/quantor/quantor.pb \
		--input_checkpoint=$(QUANTOR_BASE)/inceptionV3/quantor/model.ckpt \
		--input_binary=true --output_graph=$(QUANTOR_BASE)/inceptionV3/quantor/frozen.pb \
		--output_node_names=InceptionV3/Predictions/Reshape
	@ python $(TOOLS_BASE)/save_summaries.py $(QUANTOR_BASE)/inceptionV3/quantor/frozen.pb
	@ python $(QUANTOR_BASE)/eval_frozen.py \
		--dataset_name=imagenet \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--output_node_name=InceptionV3/Predictions/Reshape \
		--input_size=299 \
		--frozen_pb=$(QUANTOR_BASE)/inceptionV3/quantor/frozen.pb --max_num_batches=50
		# --summary_dir=$(QUANTOR_BASE)/inceptionV3/quantor/summary/$@

# TODO(yumaokao): should remove --allow_custom_ops after QUANTIZED is added
toco_quantor_inceptionV3:
	@ mkdir -p $(QUANTOR_BASE)/inceptionV3/quantor/dots
	$(TF_BASE)/bazel-bin/tensorflow/contrib/lite/toco/toco \
		--input_file=$(QUANTOR_BASE)/inceptionV3/quantor/frozen.pb \
		--input_format=TENSORFLOW_GRAPHDEF  --output_format=TFLITE \
		--output_file=$(QUANTOR_BASE)/inceptionV3/quantor/model.lite \
		--mean_values=128 --std_values=127 \
		--inference_type=QUANTIZED_UINT8 \
		--inference_input_type=QUANTIZED_UINT8 --input_arrays=input \
		--output_arrays=InceptionV3/Predictions/Reshape --input_shapes=1,299,299,3 \
		--default_ranges_min=0 --default_ranges_max=6 --partial_quant --allow_custom_ops \
		--dump_graphviz=$(QUANTOR_BASE)/inceptionV3/quantor/dots

toco_inceptionV3:
	@ mkdir -p $(QUANTOR_BASE)/inceptionV3/dots
	@ $(TF_BASE)/bazel-bin/tensorflow/contrib/lite/toco/toco \
		--input_file=$(QUANTOR_BASE)/inceptionV3/frozen_inceptionV3.pb \
		--input_format=TENSORFLOW_GRAPHDEF  --output_format=TFLITE \
		--output_file=$(QUANTOR_BASE)/inceptionV3/float_model.lite \
		--inference_type=FLOAT \
		--inference_input_type=FLOAT --input_arrays=input \
		--output_arrays=InceptionV3/Predictions/Reshape --input_shapes=1,299,299,3 \
		--dump_graphviz=$(QUANTOR_BASE)/inceptionV3/dots

eval_quantor_inceptionV3_tflite:
	@ python $(QUANTOR_BASE)/eval_tflite_imagenet.py \
		--summary_dir=$(QUANTOR_BASE)/inceptionV3/quantor/summary/$@ \
		--dataset_name=imagenet --dataset_split_name=test \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--tflite_model=$(QUANTOR_BASE)/inceptionV3/quantor/model.lite \
		--inference_type=uint8 --tensorflow_dir=$(TF_BASE) \
		--max_num_batches=50 --input_size=299

eval_inceptionV3_tflite:
	@ python $(QUANTOR_BASE)/eval_tflite.py \
		--summary_dir=$(QUANTOR_BASE)/inceptionV3/quantor/summary/$@ \
		--dataset_name=imagenet --dataset_split_name=test \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--tflite_model=$(QUANTOR_BASE)/inceptionV3/float_model.lite --tensorflow_dir=$(TF_BASE) \
		--max_num_batches=50 --input_size=299


########################################################
# compare_toco
########################################################
compare_toco_inceptionV3_float:
	@ python $(QUANTOR_BASE)/compare_toco.py \
		--dataset_name=imagenet \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--frozen_pb=$(QUANTOR_BASE)/inceptionV3/frozen_inceptionV3.pb \
		--max_num_batches=100 \
		--output_node_name=InceptionV3/Predictions/Reshape \
		--tensorflow_dir=$(TF_BASE) \
		--toco_inference_type=float \
		--input_size=299 \
		--evaluation_mode=accuracy \
		--dump_data=False

compare_toco_inceptionV3_uint8:
	@ python $(QUANTOR_BASE)/compare_toco.py \
		--dataset_name=imagenet \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--frozen_pb=$(QUANTOR_BASE)/inceptionV3/quantor/frozen.pb \
		--max_num_batches=100 \
		--output_node_name=InceptionV3/Predictions/Reshape \
		--tensorflow_dir=$(TF_BASE) \
		--toco_inference_type=uint8 \
		--input_size=299 \
		--evaluation_mode=accuracy \
		--dump_data=False