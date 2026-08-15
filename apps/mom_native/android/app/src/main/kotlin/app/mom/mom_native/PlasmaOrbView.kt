package app.mom.mom_native

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.os.SystemClock
import android.util.AttributeSet
import android.view.View
import java.util.Random
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

class PlasmaOrbView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : View(context, attrs, defStyleAttr) {
    companion object {
        private const val APPROVED_ORB_ASSET =
            "flutter_assets/assets/photopea_background_remover_1786650252951.png"
    }

    private enum class OrbState(
        val wireName: String,
        val branches: Int,
        val edgeArcs: Int,
        val jitter: Float,
        val thickness: Float,
        val pulseSpeed: Float,
        val frameDelayMs: Long,
    ) {
        IDLE("idle", 5, 1, 0.55f, 0.72f, 1.15f, 42L),
        LISTENING("listening", 10, 3, 0.92f, 1.02f, 2.20f, 24L),
        THINKING("thinking", 12, 4, 1.18f, 0.92f, 3.15f, 20L),
        TALKING("talking", 14, 5, 1.32f, 1.28f, 4.20f, 16L),
        ERROR("error", 4, 2, 0.75f, 1.12f, 0.75f, 70L),
    }

    private var orbState = OrbState.IDLE
    private var running = false

    private val approvedArtwork: Bitmap? by lazy {
        runCatching {
            context.assets.open(APPROVED_ORB_ASSET).use { stream -> BitmapFactory.decodeStream(stream) }
        }.getOrNull()
    }

    private val artworkPaint =
        Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#A020F0")
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        maskFilter = BlurMaskFilter(15f, BlurMaskFilter.Blur.NORMAL)
    }

    private val corePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }

    private val centerGlowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#A020F0")
        style = Paint.Style.FILL
        maskFilter = BlurMaskFilter(18f, BlurMaskFilter.Blur.NORMAL)
    }

    init {
        // BlurMaskFilter is consistent on the small orb surface in software.
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    fun setOrbState(rawState: String?) {
        val next = OrbState.values().firstOrNull { it.wireName == rawState }
            ?: OrbState.IDLE
        if (next == orbState) return
        orbState = next
        invalidate()
    }

    fun dispose() {
        running = false
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        running = true
        invalidate()
    }

    override fun onDetachedFromWindow() {
        running = false
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val artwork = approvedArtwork ?: return
        val side = min(width, height).toFloat()
        if (side <= 0f) return

        val left = (width - side) / 2f
        val top = (height - side) / 2f
        val artworkRect = RectF(left, top, left + side, top + side)

        // The approved static orb remains the visual source of truth.
        canvas.drawBitmap(artwork, null, artworkRect, artworkPaint)

        val centerX = width / 2f
        val centerY = height / 2f
        val radius = side * 0.47f
        val scale = side / 300f
        val seconds = SystemClock.uptimeMillis() / 1000f
        val pulse = 0.86f + 0.14f *
            sin((seconds * orbState.pulseSpeed).toDouble()).toFloat()
        val frame = SystemClock.uptimeMillis() / orbState.frameDelayMs
        val random = Random(frame + orbState.ordinal * 10_000L)

        centerGlowPaint.alpha = (92f * pulse).toInt().coerceIn(0, 255)
        canvas.drawCircle(
            centerX,
            centerY,
            (14f + 9f * pulse) * scale,
            centerGlowPaint,
        )

        repeat(orbState.branches) { index ->
            val baseAngle = index * (360f / orbState.branches)
            val drift = sin(
                (seconds * orbState.pulseSpeed + index * 1.71f).toDouble(),
            ).toFloat() * 8f
            val targetAngle = baseAngle + drift + random.nextFloat() * 8f
            val angleRad = Math.toRadians(targetAngle.toDouble())
            val targetX = centerX + radius * cos(angleRad).toFloat()
            val targetY = centerY + radius * sin(angleRad).toFloat()
            drawLightningBolt(
                canvas,
                centerX,
                centerY,
                targetX,
                targetY,
                random,
                scale,
                pulse,
            )
        }

        repeat(orbState.edgeArcs) {
            drawEdgeArc(canvas, centerX, centerY, radius, random, scale, pulse)
        }

        if (running) postInvalidateDelayed(orbState.frameDelayMs)
    }

    private fun drawLightningBolt(
        canvas: Canvas,
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
        random: Random,
        scale: Float,
        pulse: Float,
    ) {
        val path = Path().apply { moveTo(startX, startY) }
        val segments = 7
        val thickness =
            (2.2f + random.nextFloat() * 3.4f) * orbState.thickness * scale
        val jitter = 22f * orbState.jitter * scale

        glowPaint.strokeWidth = thickness + 7f * scale
        glowPaint.alpha = (180f * pulse).toInt().coerceIn(0, 255)
        corePaint.strokeWidth = (thickness * 0.38f).coerceAtLeast(0.8f)
        corePaint.alpha = (245f * pulse).toInt().coerceIn(0, 255)

        for (segment in 1..segments) {
            val fraction = segment.toFloat() / segments
            val idealX = startX + (endX - startX) * fraction
            val idealY = startY + (endY - startY) * fraction
            if (segment == segments) {
                path.lineTo(endX, endY)
            } else {
                path.lineTo(
                    idealX + (random.nextFloat() - 0.5f) * jitter,
                    idealY + (random.nextFloat() - 0.5f) * jitter,
                )
            }
        }

        canvas.drawPath(path, glowPaint)
        canvas.drawPath(path, corePaint)
    }

    private fun drawEdgeArc(
        canvas: Canvas,
        centerX: Float,
        centerY: Float,
        radius: Float,
        random: Random,
        scale: Float,
        pulse: Float,
    ) {
        val startAngle = random.nextFloat() * 360f
        val endAngle = startAngle + 18f + random.nextFloat() * 24f
        val startRad = Math.toRadians(startAngle.toDouble())
        val endRad = Math.toRadians(endAngle.toDouble())
        val midRad = Math.toRadians(((startAngle + endAngle) / 2f).toDouble())

        val path = Path().apply {
            moveTo(
                centerX + radius * cos(startRad).toFloat(),
                centerY + radius * sin(startRad).toFloat(),
            )
            val burstOutward = radius + (5f + random.nextFloat() * 12f) * scale
            lineTo(
                centerX + burstOutward * cos(midRad).toFloat(),
                centerY + burstOutward * sin(midRad).toFloat(),
            )
            lineTo(
                centerX + radius * cos(endRad).toFloat(),
                centerY + radius * sin(endRad).toFloat(),
            )
        }

        glowPaint.strokeWidth = 6f * scale * orbState.thickness
        glowPaint.alpha = (170f * pulse).toInt().coerceIn(0, 255)
        corePaint.strokeWidth = (1.7f * scale).coerceAtLeast(0.8f)
        corePaint.alpha = (235f * pulse).toInt().coerceIn(0, 255)
        canvas.drawPath(path, glowPaint)
        canvas.drawPath(path, corePaint)
    }
}
