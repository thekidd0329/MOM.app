# PROPOSED: Model Runtime Boundary

Status: proposed.

The language model is not the authority over device permissions, private storage, network access, sensors, or user data.

Proposed boundary:

`MOM cognition -> requests capability/data -> application policy layer decides -> permitted result returned`

The model can ask for information. It cannot grant itself access.

Local testing and hosted inference should expose the same logical interface so development does not fork MOM into two different products.