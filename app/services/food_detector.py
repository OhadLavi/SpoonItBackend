async def detect_food_in_image(
    self,
    image_input: Union[bytes, Image.Image],
    threshold: float = 0.25
) -> Tuple[bool, float]:
    """
    Detect if an image contains food.
    """
    self._initialize_session()

    if self._session is None:
        # If ONNX not available, assume all images might be food
        return True, 0.5

    try:
        loop = asyncio.get_running_loop()

        # Prepare raw bytes for executor
        if isinstance(image_input, Image.Image):
            buffer = BytesIO()
            image_input.save(buffer, format="JPEG")
            image_data = buffer.getvalue()
        else:
            image_data = image_input

        # Load + preprocess off the event loop
        input_tensor = await loop.run_in_executor(
            None,
            lambda: self._load_and_preprocess(image_data)
        )

        input_name = self._session.get_inputs()[0].name

        # Run inference off the event loop
        outputs = await loop.run_in_executor(
            None,
            lambda: self._session.run(None, {input_name: input_tensor})
        )

        logits = outputs[0][0]
        probabilities = self._softmax(logits)

        top_5_indices = np.argsort(probabilities)[-5:][::-1]

        is_food, score = self._is_food_class(
            top_5_indices.tolist(),
            probabilities,
            threshold
        )

        logger.debug(
            f"Food detection: is_food={is_food}, "
            f"score={score:.3f}, threshold={threshold}"
        )

        return is_food, score

    except Exception as e:
        logger.warning(f"Food detection failed: {e}")
        return True, 0.5
