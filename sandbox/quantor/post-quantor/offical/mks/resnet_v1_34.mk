# float model
QUANTOR_RESNET_V1_34_TARGETS := freeze_resnet_v1_34
QUANTOR_RESNET_V1_34_TARGETS += eval_resnet_v1_34_frozen
# float model
QUANTOR_RESNET_V1_34_TARGETS += toco_resnet_v1_34
QUANTOR_RESNET_V1_34_TARGETS += eval_resnet_v1_34_tflite
# uint8 model
QUANTOR_RESNET_V1_34_TARGETS += quantor_resnet_v1_34_frozen
QUANTOR_RESNET_V1_34_TARGETS += toco_quantor_resnet_v1_34
QUANTOR_RESNET_V1_34_TARGETS += eval_quantor_resnet_v1_34_tflite

.PHONY: train_resnet_v1_34 eval_resnet_v1_34
.PHONY: ${QUANTOR_RESNET_V1_34_TARGETS}
.PHONY: quantor_resnet_v1_34
.PHONY: compare_toco_resnet_v1_34_float compare_toco_resnet_v1_34_uint8

########################################################
# should already defined these variables
########################################################
# TFLITE_ROOT_PATH := /home/tflite
# TF_BASE := $(TFLITE_ROOT_PATH)/tensorflow
# TF_SLIM_BASE := $(TFLITE_ROOT_PATH)/models/research/slim
# DATASET_BASE := $(TFLITE_ROOT_PATH)/datasets
# QUANTOR_BASE := $(TFLITE_ROOT_PATH)/sandbox/quantor

########################################################
# for resnet_v1_34
########################################################
TF_RESNET_BASE := $(TFLITE_ROOT_PATH)/models/official/resnet
TF_MODELS_BASE := $(TFLITE_ROOT_PATH)/models

train_resnet_v1_34:
	@ PYTHONPATH=${TF_MODELS_BASE} \
	  python $(TF_RESNET_BASE)/imagenet_main.py --data_dir=$(DATASET_BASE)/imagenet \
		--resnet_size=34 --version 1 --model_dir=./resnet_v1_34

eval_resnet_v1_34:
	@ cd $(TF_SLIM_BASE) && python eval_image_classifier.py \
		--checkpoint_path=$(QUANTOR_BASE)/resnet_v1_34/resnet_v1_34.ckpt \
		--eval_dir=$(QUANTOR_BASE)/resnet_v1_34 \
		--dataset_name=imagenet --dataset_split_name=validation \
		--labels_offset=1 \
		--dataset_dir=$(DATASET_BASE)/imagenet --model_name=resnet_v1_34 --max_num_batches=200

quantor_resnet_v1_34: ${QUANTOR_RESNET_V1_34_TARGETS}

# sub targets
freeze_resnet_v1_34:
	@ cd $(TF_SLIM_BASE) && python export_inference_graph.py \
		--alsologtostderr --labels_offset=1 \
		--model_name=resnet_v1_34 --dataset_name=imagenet \
		--output_file=$(QUANTOR_BASE)/resnet_v1_34/resnet_v1_34_inf_graph.pb
	@ save_summaries $(QUANTOR_BASE)/resnet_v1_34/resnet_v1_34_inf_graph.pb
	@ cd $(TF_BASE) && bazel-bin/tensorflow/python/tools/freeze_graph \
		--input_graph=$(QUANTOR_BASE)/resnet_v1_34/resnet_v1_34_inf_graph.pb \
		--input_checkpoint=$(QUANTOR_BASE)/resnet_v1_34/resnet_v1_34.ckpt \
		--input_binary=true --output_graph=$(QUANTOR_BASE)/resnet_v1_34/frozen_resnet_v1_34.pb \
		--output_node_names=resnet_v1_34/predictions/Reshape_1
	@ cd $(TF_BASE) && bazel-bin/tensorflow/tools/graph_transforms/transform_graph \
		--in_graph=$(QUANTOR_BASE)/resnet_v1_34/frozen_resnet_v1_34.pb \
		--out_graph=$(QUANTOR_BASE)/resnet_v1_34/frozen_resnet_v1_34_tmp.pb \
		--inputs=input \
		--outputs=resnet_v1_34/predictions/Reshape_1 \
		--transforms='fold_old_batch_norms fold_batch_norms'
	@ mv $(QUANTOR_BASE)/resnet_v1_34/frozen_resnet_v1_34_tmp.pb $(QUANTOR_BASE)/resnet_v1_34/frozen_resnet_v1_34.pb
	@ save_summaries $(QUANTOR_BASE)/resnet_v1_34/frozen_resnet_v1_34.pb

eval_resnet_v1_34_frozen:
	@ eval_frozen \
		--dataset_name=imagenet \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--output_node_name=resnet_v1_34/predictions/Reshape_1 \
		--input_size=224 --labels_offset=1 --preprocess_name=vgg \
		--frozen_pb=$(QUANTOR_BASE)/resnet_v1_34/frozen_resnet_v1_34.pb --max_num_batches=200

quantor_resnet_v1_34_frozen:
	@ quantor_frozen \
		--dataset_name=imagenet \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--frozen_pb=$(QUANTOR_BASE)/resnet_v1_34/frozen_resnet_v1_34.pb \
		--output_node_name=resnet_v1_34/predictions/Reshape_1 \
		--input_size=224 --labels_offset=1 --preprocess_name=vgg \
		--output_dir=$(QUANTOR_BASE)/resnet_v1_34/quantor --max_num_batches=200
	@ python $(TF_BASE)/bazel-bin/tensorflow/python/tools/freeze_graph \
		--input_graph=$(QUANTOR_BASE)/resnet_v1_34/quantor/quantor.pb \
		--input_checkpoint=$(QUANTOR_BASE)/resnet_v1_34/quantor/model.ckpt \
		--input_binary=true --output_graph=$(QUANTOR_BASE)/resnet_v1_34/quantor/frozen.pb \
		--output_node_names=resnet_v1_34/predictions/Reshape_1
	@ save_summaries $(QUANTOR_BASE)/resnet_v1_34/quantor/frozen.pb
	@ eval_frozen \
		--dataset_name=imagenet \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--output_node_name=resnet_v1_34/predictions/Reshape_1 \
		--input_size=224 --labels_offset=1 --preprocess_name=vgg \
		--frozen_pb=$(QUANTOR_BASE)/resnet_v1_34/quantor/frozen.pb --max_num_batches=200

# --default_ranges_min=0 --default_ranges_max=10
toco_quantor_resnet_v1_34:
	@ mkdir -p $(QUANTOR_BASE)/resnet_v1_34/quantor/dots
	@ $(TF_BASE)/bazel-bin/tensorflow/contrib/lite/toco/toco \
		--input_file=$(QUANTOR_BASE)/resnet_v1_34/quantor/frozen.pb \
		--input_format=TENSORFLOW_GRAPHDEF  --output_format=TFLITE \
		--output_file=$(QUANTOR_BASE)/resnet_v1_34/quantor/model.lite \
		--mean_values=114.8 --std_values=1.0 \
		--inference_type=QUANTIZED_UINT8 \
		--inference_input_type=QUANTIZED_UINT8 --input_arrays=input \
		--output_arrays=resnet_v1_34/predictions/Reshape_1 --input_shapes=10,224,224,3 \
		--dump_graphviz=$(QUANTOR_BASE)/resnet_v1_34/quantor/dots

toco_resnet_v1_34:
	@ mkdir -p $(QUANTOR_BASE)/resnet_v1_34/dots
	@ $(TF_BASE)/bazel-bin/tensorflow/contrib/lite/toco/toco \
		--input_file=$(QUANTOR_BASE)/resnet_v1_34/frozen_resnet_v1_34.pb \
		--input_format=TENSORFLOW_GRAPHDEF  --output_format=TFLITE \
		--output_file=$(QUANTOR_BASE)/resnet_v1_34/float_model.lite \
		--inference_type=FLOAT \
		--inference_input_type=FLOAT --input_arrays=input \
		--output_arrays=resnet_v1_34/predictions/Reshape_1 --input_shapes=1,224,224,3 \
		--dump_graphviz=$(QUANTOR_BASE)/resnet_v1_34/dots

eval_quantor_resnet_v1_34_tflite:
	@ echo $@
	@ eval_tflite \
		--summary_dir=$(QUANTOR_BASE)/resnet_v1_34/quantor/summary/$@ \
		--dataset_name=imagenet --dataset_split_name=test \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--tflite_model=$(QUANTOR_BASE)/resnet_v1_34/quantor/model.lite \
		--inference_type=uint8 --tensorflow_dir=$(TF_BASE) \
		--labels_offset=1 --preprocess_name=vgg \
		--max_num_batches=1000 --input_size=224 --batch_size=10

eval_resnet_v1_34_tflite:
	@ echo $@
	@ eval_tflite \
		--summary_dir=$(QUANTOR_BASE)/resnet_v1_34/quantor/summary/$@ \
		--dataset_name=imagenet --dataset_split_name=test \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--tflite_model=$(QUANTOR_BASE)/resnet_v1_34/float_model.lite --tensorflow_dir=$(TF_BASE) \
		--labels_offset=1 --preprocess_name=vgg \
		--max_num_batches=10000 --input_size=224


########################################################
# compare_toco
########################################################
compare_toco_resnet_v1_34_float:
	@ compare_toco \
		--dataset_name=imagenet \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--frozen_pb=$(QUANTOR_BASE)/resnet_v1_34/frozen_resnet_v1_34.pb \
		--max_num_batches=1000 \
		--output_node_name=resnet_v1_34/predictions/Reshape_1 \
		--tensorflow_dir=$(TF_BASE) \
		--toco_inference_type=float \
		--input_size=224 \
		--labels_offset=1 --preprocess_name=vgg \
		--dump_data=False

compare_toco_resnet_v1_34_uint8:
	@ compare_toco \
		--dataset_name=imagenet \
		--dataset_dir=$(DATASET_BASE)/imagenet \
		--frozen_pb=$(QUANTOR_BASE)/resnet_v1_34/quantor/frozen.pb \
		--max_num_batches=1000 \
		--tensorflow_dir=$(TF_BASE) \
		--output_node_name=resnet_v1_34/predictions/Reshape_1 \
		--toco_inference_type=uint8 \
		--input_size=224 \
		--labels_offset=1 --preprocess_name=vgg \
		--dump_data=False \
		--extra_toco_flags='--mean_values=114.8 --std_values=1.0'
