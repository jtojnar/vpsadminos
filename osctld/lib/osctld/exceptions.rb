module OsCtld
  include OsCtl::Lib::Exceptions

  class CommandFailed < StandardError ; end
  class CGroupSubsystemNotFound < StandardError ; end
  class CGroupParameterNotFound < StandardError ; end
end
