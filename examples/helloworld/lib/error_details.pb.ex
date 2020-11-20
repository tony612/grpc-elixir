defmodule Google.Rpc.RetryInfo do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          retry_delay: Google.Protobuf.Duration.t() | nil
        }
  defstruct [:retry_delay]

  field :retry_delay, 1, type: Google.Protobuf.Duration
end

defmodule Google.Rpc.DebugInfo do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          stack_entries: [String.t()],
          detail: String.t()
        }
  defstruct [:stack_entries, :detail]

  field :stack_entries, 1, repeated: true, type: :string
  field :detail, 2, type: :string
end

defmodule Google.Rpc.QuotaFailure.Violation do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          subject: String.t(),
          description: String.t()
        }
  defstruct [:subject, :description]

  field :subject, 1, type: :string
  field :description, 2, type: :string
end

defmodule Google.Rpc.QuotaFailure do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          violations: [Google.Rpc.QuotaFailure.Violation.t()]
        }
  defstruct [:violations]

  field :violations, 1, repeated: true, type: Google.Rpc.QuotaFailure.Violation
end

defmodule Google.Rpc.PreconditionFailure.Violation do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          type: String.t(),
          subject: String.t(),
          description: String.t()
        }
  defstruct [:type, :subject, :description]

  field :type, 1, type: :string
  field :subject, 2, type: :string
  field :description, 3, type: :string
end

defmodule Google.Rpc.PreconditionFailure do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          violations: [Google.Rpc.PreconditionFailure.Violation.t()]
        }
  defstruct [:violations]

  field :violations, 1, repeated: true, type: Google.Rpc.PreconditionFailure.Violation
end

defmodule Google.Rpc.BadRequest.FieldViolation do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          field: String.t(),
          description: String.t()
        }
  defstruct [:field, :description]

  field :field, 1, type: :string
  field :description, 2, type: :string
end

defmodule Google.Rpc.BadRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          field_violations: [Google.Rpc.BadRequest.FieldViolation.t()]
        }
  defstruct [:field_violations]

  field :field_violations, 1, repeated: true, type: Google.Rpc.BadRequest.FieldViolation
end

defmodule Google.Rpc.RequestInfo do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          request_id: String.t(),
          serving_data: String.t()
        }
  defstruct [:request_id, :serving_data]

  field :request_id, 1, type: :string
  field :serving_data, 2, type: :string
end

defmodule Google.Rpc.ResourceInfo do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          resource_type: String.t(),
          resource_name: String.t(),
          owner: String.t(),
          description: String.t()
        }
  defstruct [:resource_type, :resource_name, :owner, :description]

  field :resource_type, 1, type: :string
  field :resource_name, 2, type: :string
  field :owner, 3, type: :string
  field :description, 4, type: :string
end

defmodule Google.Rpc.Help.Link do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          description: String.t(),
          url: String.t()
        }
  defstruct [:description, :url]

  field :description, 1, type: :string
  field :url, 2, type: :string
end

defmodule Google.Rpc.Help do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          links: [Google.Rpc.Help.Link.t()]
        }
  defstruct [:links]

  field :links, 1, repeated: true, type: Google.Rpc.Help.Link
end

defmodule Google.Rpc.LocalizedMessage do
  @moduledoc false
  use Protobuf, syntax: :proto3

  @type t :: %__MODULE__{
          locale: String.t(),
          message: String.t()
        }
  defstruct [:locale, :message]

  field :locale, 1, type: :string
  field :message, 2, type: :string
end
