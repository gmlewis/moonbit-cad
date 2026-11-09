///|
/// Explicit trait-method promotion declarations for the derived `Eq` and
/// `Debug` implementations, mirroring the sibling `gmlewis/urdf` package.

///|
pub extend ConnectionKind with Debug::{to_repr}

///|
pub extend ConnectionKind with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend ConnectionKind with Eq::{not_equal}

///|
pub extend JointSpec with Debug::{to_repr}

///|
pub extend JointSpec with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend JointSpec with Eq::{not_equal}
