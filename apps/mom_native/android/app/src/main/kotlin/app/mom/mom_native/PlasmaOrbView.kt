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
import android.util.AttributeSet
import android.util.Base64
import android.view.View
import java.util.Random
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

class PlasmaOrbView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null, defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    companion object {
        private const val CANONICAL_2615_ASSET =
            "flutter_assets/assets/ui/2615.b64.txt"
    }

    private val random = Random()

    // The approved 2615 artwork is the orb. Matt's live plasma is only an
    // animation layer over this source and must never replace it.
    private val canonicalArtwork: Bitmap? by lazy { loadCanonicalArtwork() }
    private val artworkPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    // Paint for the thick purple outer glow.
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#A020F0")
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        maskFilter = BlurMaskFilter(15f, BlurMaskFilter.Blur.NORMAL)
    }

    // Paint for the thin white-hot electrical core.
    private val corePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val artwork = canonicalArtwork ?: return
        val side = min(width, height).toFloat()
        val left = (width - side) / 2f
        val top = (height - side) / 2f
        val artworkRect = RectF(left, top, left + side, top + side)

        // 1. DRAW THE REAL ORB FIRST. Never procedurally substitute for 2615.
        canvas.drawBitmap(artwork, null, artworkRect, artworkPaint)

        val centerX = width / 2f
        val centerY = height / 2f
        val radius = side * 0.47f

        // 2. MATT'S LIVE CENTRAL ENERGY LAYER.
        canvas.drawCircle(centerX, centerY, 20f, corePaint)

        // 3. MATT'S MOVING MAIN LIGHTNING FILAMENTS.
        val numberOfBranches = 8
        for (i in 0 until numberOfBranches) {
            val targetAngle = (i * (360f / numberOfBranches)) + random.nextFloat() * 15f
            val angleRad = Math.toRadians(targetAngle.toDouble())

            val targetX = centerX + radius * cos(angleRad).toFloat()
            val targetY = centerY + radius * sin(angleRad).toFloat()
            drawLightningBolt(canvas, centerX, centerY, targetX, targetY)
        }

        // 4. MATT'S MOVING EDGE ARCS.
        val edgeArcsCount = 4
        for (i in 0 until edgeArcsCount) {
            drawEdgeArc(canvas, centerX, centerY, radius)
        }

        postInvalidateOnAnimation()
    }

    private fun loadCanonicalArtwork(): Bitmap? {
        return try {
            val encoded = context.assets.open(CANONICAL_2615_ASSET)
                .bufferedReader()
                .use { it.readText() }
                .trim()
            val bytes = Base64.decode(encoded, Base64.DEFAULT)
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } catch (_: Exception) {
            // Failing closed is intentional: a missing source image must never
            // silently fall back to a different procedural orb.
            null
        }
    }

    private fun drawLightningBolt(
        canvas: Canvas,
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
    ) {
        val path = Path()
        path.moveTo(startX, startY)

        val segments = 6
        val currentThickness = 3f + random.nextFloat() * 5f
        glowPaint.strokeWidth = currentThickness + 8f
        corePaint.strokeWidth = currentThickness * 0.4f

        for (i in 1..segments) {
            val fraction = i.toFloat() / segments
            val idealX = startX + (endX - startX) * fraction
            val idealY = startY + (endY - startY) * fraction
            val jitter = 25f
            val currentX = idealX + (random.nextFloat() - 0.5f) * jitter
            val currentY = idealY + (random.nextFloat() - 0.5f) * jitter

            if (i == segments) {
                path.lineTo(endX, endY)
            } else {
                path.lineTo(currentX, currentY)
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
    ) {
        val path = Path()

        val startAngle = random.nextFloat() * 360f
        val endAngle = startAngle + 20f + random.nextFloat() * 20f

        val startRad = Math.toRadians(startAngle.toDouble())
        val endRad = Math.toRadians(endAngle.toDouble())

        val startX = centerX + radius * cos(startRad).toFloat()
        val startY = centerY + radius * sin(startRad).toFloat()
        val endX = centerX + radius * cos(endRad).toFloat()
        val endY = centerY + radius * sin(endRad).toFloat()

        path.moveTo(startX, startY)

        val midAngle = (startAngle + endAngle) / 2f
        val midRad = Math.toRadians(midAngle.toDouble())
        val burstOutward = radius + (5f + random.nextFloat() * 15f)
        val midX = centerX + burstOutward * cos(midRad).toFloat()
        val midY = centerY + burstOutward * sin(midRad).toFloat()

        path.lineTo(midX, midY)
        path.lineTo(endX, endY)

        glowPaint.strokeWidth = 6f
        corePaint.strokeWidth = 2f

        canvas.drawPath(path, glowPaint)
        canvas.drawPath(path, corePaint)
    }
}
